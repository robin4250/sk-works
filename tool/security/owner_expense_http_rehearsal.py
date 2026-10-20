#!/usr/bin/env python3
"""Disposable GoTrue-issued JWT/Data API checks on a new restored DB clone."""
import base64
import hashlib
import hmac
import ipaddress
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import sys
import tempfile
import time
import selectors
import threading
import uuid
from urllib.parse import urlencode
import owner_common_http_rehearsal as shared
common=shared.common
check=shared.check
jwt=shared.jwt
StartupCapture=shared.StartupCapture
HttpExecFailure=shared.HttpExecFailure
clone_command=shared.clone_command
image_check=shared.image_check
internal_endpoint=shared.internal_endpoint
identity_sql=shared.identity_sql
auth_database_url=shared.auth_database_url
auth_scope_sql=shared.auth_scope_sql
auth_scope_allowed=shared.auth_scope_allowed
auth_catalog_sql=shared.auth_catalog_sql
safe_service_state=shared.safe_service_state

AUTH_IMAGE='supabase/gotrue@sha256:1736a63078f5922b198c4cbe50f80ab9a2d3b54fe8b7b6cfb2e9dc5dbbc12c6b'
REST_IMAGE='postgrest/postgrest@sha256:d155c6718ed9a9f990d159a2ab7c0a3f16944dbb6d0a0344557421042acfe0df'
DOCUMENT_HASH='558302f271e0033a2a76299c16ea8b78'


class ExpenseHttp(shared.InternalCurlHttp):
    """Add only the pinned REST negotiation header; retain every shared check."""
    def config(self,service,path,token,body,method,headers):
        headers=dict(headers or {})
        directional=headers.pop('x-sko-payment-source-version',None)
        if directional is not None:
            check(service=='rest' and directional=='2','expense_header_invalid')
        data=super().config(service,path,token,body,method,headers)
        if directional is not None:
            data+=b'header = "x-sko-payment-source-version: 2"\n'
        check(len(data)<=65536,'http_request_too_large')
        return data


def expense_rpc(http,name,token,body,supported):
    check(name in ('read_expense_document','payment_certificate_detail_rows'),'expense_rpc_invalid')
    return http.call('rest','/rpc/'+name,token,body,headers={'x-sko-payment-source-version':'2'} if supported else None)


def load_bundle(directory):
    manifest=json.loads((directory/'runtime_manifest.json').read_text())
    for name,expected in manifest['files'].items():
        path=directory/name
        check(path.is_file() and not path.is_symlink() and path.parent==directory,'runtime_file_invalid')
        check(hashlib.sha256(path.read_bytes()).hexdigest()==expected,'runtime_hash_mismatch')
    bundle=json.loads((directory/'expense_off_rehearsal_bundle.json').read_text())
    check(set(bundle['files'])==set(manifest['bundle_files']),'expense_bundle_shape_changed')
    for name,expected in manifest['bundle_files'].items():
        check(hashlib.sha256(bundle['files'][name].encode()).hexdigest()==expected,'expense_source_hash_mismatch')
    return bundle


def conversion_for_actor(bundle,actor,session):
    actor=str(uuid.UUID(actor));session=str(uuid.UUID(session))
    source=bundle['files']['conversion_scenario.sql']
    start=source.index(' SELECT count(*) INTO actor_count FROM public.company_members')
    end=source.index(' IF auth.uid() IS DISTINCT FROM actor',start)
    # The original source owner/membership is untouched. Add a synthetic admin
    # to exactly that document company, and bind the claims to the issued JWT.
    replacement=""" actor:='%s'::uuid;
 IF NOT EXISTS(SELECT 1 FROM public.company_members WHERE company_id=cid AND user_id=actor AND role::text='admin')
 OR NOT EXISTS(SELECT 1 FROM auth.sessions WHERE id='%s'::uuid AND user_id=actor AND (not_after IS NULL OR not_after>clock_timestamp()))
 THEN RAISE EXCEPTION 'synthetic GoTrue admin company/session mismatch'; END IF;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated','session_id','%s')::text,true);
""" % (actor,session,session)
    return source[:start]+replacement+source[end:]


def main():
    os.umask(0o077)
    stage=None; network=None; network_id=None; containers=[]; env_files=[]; captures={}
    state={'schema':1,'verified':False,'production_connected':False,'original_restore_changed':False,
        'owner_google_login_verified':False,'real_phone_provider_verified':False,'clone_changes_committed':False}
    code=1
    try:
        check(sys.platform=='darwin','mac_required')
        check(not os.environ.get('DOCKER_HOST') and not os.environ.get('DOCKER_CONTEXT'),'docker_override_refused')
        root=Path.home()/'SKO-source-backups'; source=root/common.transport.SOURCE
        check(not any(p.is_symlink() for p in (source,*source.parents)) and not root.stat().st_mode&0o077,'private_source_required')
        original=json.loads((source/'rehearsal-status.json').read_text())
        check(original.get('archive_restore_verified') and original.get('container_stopped'),'verified_stopped_source_required')
        original_name=original['container'];check(re.fullmatch(r'sko-restore-[a-f0-9]{12}',original_name) is not None,'source_name_invalid')
        bundle=load_bundle(Path(__file__).parent)
        stage=Path(tempfile.mkdtemp(prefix='expense-http-jwt-rehearsal-',dir=root))
        env={k:v for k,v in os.environ.items() if not k.startswith('PG')}
        # Never persist raw stdout/stderr from Auth, SQL or Docker: they may contain secrets.
        def run(args,data=None,timeout=120):
            result=subprocess.run(args,env=env,input=data,stdin=subprocess.DEVNULL if data is None else None,
                stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=timeout)
            if result.returncode!=0:
                found=re.search(rb'(?:ERROR|FATAL):\s+([0-9A-Z]{5})(?:\s|$)',result.stderr)
                if found: state['last_sqlstate']=found.group(1).decode()
                raise RuntimeError('subprocess_failed')
            return result.stdout
        context=json.loads(run(['docker','context','inspect']))
        check(context[0]['Endpoints']['docker']['Host'].startswith('unix://'),'remote_docker_refused')
        src=json.loads(run(['docker','inspect',original_name]))[0]
        check(not src['State']['Running'] and src['HostConfig']['NetworkMode']=='none' and not src['HostConfig'].get('PortBindings') and src['Config']['Image']==common.transport.BASE_IMAGE and src['Config']['Labels'].get('sko-purpose')=='offline-restore','source_container_mismatch')
        state['phase']='images'
        for image in (AUTH_IMAGE,REST_IMAGE): image_check(json.loads(run(['docker','image','inspect',image]))[0],image)
        suffix=uuid.uuid4().hex[:12]; network='sko-common-http-'+suffix
        network_id=run(['docker','network','create','--internal','--driver','bridge','--label','sko-purpose=common-http-rehearsal',network]).decode().strip()
        check(re.fullmatch(r'[a-f0-9]{64}',network_id) is not None,'network_id_invalid')
        net=json.loads(run(['docker','network','inspect',network]))[0]
        check(net.get('Internal') is True and net.get('Driver')=='bridge','internal_network_required')
        cidrs=net.get('IPAM',{}).get('Config',[]);check(len(cidrs)==1,'one_internal_subnet_required')
        subnet=ipaddress.ip_network(cidrs[0]['Subnet']);check(subnet.version==4 and subnet.is_private,'private_ipv4_subnet_required')
        state['phase']='clone'
        image=run(['docker','commit',original_name],timeout=300).decode().strip()
        check(re.fullmatch(r'sha256:[a-f0-9]{64}',image) is not None,'clone_image_invalid')
        state['private_local_image']=image; db='sko-http-db-'+suffix
        # The new cloned image lacks the new HBA file: provision it in a stopped
        # intermediate container before starting PostgreSQL, never in the original.
        db_id=run(clone_command(db,image,network)).decode().strip()
        check(re.fullmatch(r'[a-f0-9]{64}',db_id) is not None,'database_container_id_invalid')
        containers.append(db_id); state['database_container']=db
        db_auth='sko_http_auth_'+suffix; db_rest='sko_http_rest_'+suffix
        hba='local all all trust\nhost postgres '+db_auth+' '+str(subnet)+' scram-sha-256\nhost postgres '+db_rest+' '+str(subnet)+' scram-sha-256\nhost all all all reject\n'
        hba_path=stage/'http-hba.conf';hba_path.write_text(hba);hba_path.chmod(0o644)
        # HBA contains no secrets; 0644 makes its Docker-copied root-owned file
        # readable by the container postgres user. The host stage remains 0700.
        run(['docker','cp',str(hba_path),db+':/tmp/sko-http-hba.conf'])
        run(['docker','start',db])
        for _ in range(60):
            ready=subprocess.run(['docker','exec',db,'pg_isready','-h','/tmp','-U','postgres'],env=env,stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=5)
            if ready.returncode==0: break
            time.sleep(1)
        else: raise RuntimeError('database_not_ready')
        db_info=json.loads(run(['docker','inspect',db]))[0]
        check(set(db_info['NetworkSettings']['Networks'])=={network} and not db_info['HostConfig'].get('PortBindings'),'database_not_internal_only')
        def query(sql,role='postgres'):
            return run(['docker','exec','-i',db,'psql','-X','-w','-h','/tmp','-U',role,'-d','postgres','-q','-A','-t','-v','ON_ERROR_STOP=1','-v','VERBOSITY=sqlstate'],("SET statement_timeout='60s';SET lock_timeout='3s';\n"+sql).encode()).decode().strip()
        def value(sql): return query(sql).splitlines()[-1]
        check(value('SHOW cron.launch_active_jobs;')=='off','cron_not_disabled')
        query(common.transport.DATABASE_BASELINE_SQL,role='supabase_admin')
        state['phase']='off_install_clone_only'
        before=json.loads(value(bundle['queries']['catalogSql']))
        business=value(bundle['queries']['defaultOffBusinessHashSql'])
        for filename,content in bundle['files'].items(): (stage/filename).write_text(content)
        (stage/'generate.mjs').write_text(common.transport.GENERATOR)
        (stage/'input.json').write_text(json.dumps({'before':before,'business':business}))
        node_info=json.loads(run(['docker','image','inspect',common.transport.NODE_IMAGE]))[0]
        node_id=node_info['Id'];check(re.fullmatch(r'sha256:[a-f0-9]{64}',node_id) is not None,'generator_image_invalid')
        run(['docker','run','--rm','--network=none','--user',f'{os.getuid()}:{os.getgid()}',
            '--mount',f'type=bind,source={stage},target=/work','--workdir','/work',node_id,'node','generate.mjs'])
        query((stage/'generated.sql').read_text())
        check(value(bundle['queries']['defaultOffBusinessHashSql'])==business,'off_install_business_changed')
        state['off_install_verified']=True
        scope_rows=json.loads(value("SELECT coalesce(jsonb_agg(jsonb_build_object('company_id',p.company_id,'document_id',p.id)),'[]'::jsonb) FROM public.payment_certificates p WHERE md5(to_jsonb(p)::text)='"+DOCUMENT_HASH+"' AND p.status='draft';"))
        check(len(scope_rows)==1,'protected_legacy_draft_required');scope=scope_rows[0]
        for key in ('company_id','document_id'):check(str(uuid.UUID(scope[key]))==scope[key],'scope_uuid_invalid')
        def identity_fingerprint(excluded): return value(identity_sql(excluded))
        original_identity=identity_fingerprint([])
        pw_auth=secrets.token_hex(32);pw_rest=secrets.token_hex(32);secret=secrets.token_hex(48)
        state['phase']='synthetic_database_roles'
        query("SET password_encryption='scram-sha-256';CREATE ROLE "+db_auth+" LOGIN INHERIT PASSWORD '"+pw_auth+"';GRANT supabase_auth_admin TO "+db_auth+";CREATE ROLE "+db_rest+" LOGIN NOINHERIT PASSWORD '"+pw_rest+"';GRANT anon,authenticated,service_role TO "+db_rest+";GRANT CONNECT ON DATABASE postgres TO "+db_auth+','+db_rest+';',role='supabase_admin')
        state['phase']='auth_role_scope_preflight'
        state['auth_role_scope']=json.loads(query(auth_scope_sql(),role=db_auth).splitlines()[-1])
        state['auth_role_catalog']=json.loads(query(auth_catalog_sql(),role=db_auth).splitlines()[-1])
        check(auth_scope_allowed(state['auth_role_scope']),'auth_role_scope_preflight_failed')
        state['phase']='auth_rest_start'
        auth='sko-http-auth-'+suffix;rest='sko-http-rest-'+suffix
        configs={auth:{'GOTRUE_API_HOST':'0.0.0.0','GOTRUE_API_PORT':'9999','API_EXTERNAL_URL':'http://auth:9999','GOTRUE_SITE_URL':'http://fixture.invalid','GOTRUE_DB_DRIVER':'postgres','GOTRUE_DB_DATABASE_URL':auth_database_url(db_auth,pw_auth),'GOTRUE_DB_NAMESPACE':'auth','GOTRUE_JWT_SECRET':secret,'GOTRUE_JWT_EXP':'3600','GOTRUE_JWT_AUD':'authenticated','GOTRUE_JWT_DEFAULT_GROUP_NAME':'authenticated','GOTRUE_JWT_ADMIN_ROLES':'service_role','GOTRUE_DISABLE_SIGNUP':'true','GOTRUE_EXTERNAL_EMAIL_ENABLED':'true','GOTRUE_MAILER_AUTOCONFIRM':'true','GOTRUE_EXTERNAL_PHONE_ENABLED':'false','GOTRUE_EXTERNAL_GOOGLE_ENABLED':'false','GOTRUE_EXTERNAL_APPLE_ENABLED':'false','GOTRUE_LOG_LEVEL':'error'},
            rest:{'PGRST_DB_URI':'postgres://'+db_rest+':'+pw_rest+'@db:5432/postgres','PGRST_DB_SCHEMAS':'public','PGRST_DB_ANON_ROLE':'anon','PGRST_JWT_SECRET':secret,'PGRST_JWT_AUD':'authenticated','PGRST_LOG_LEVEL':'error'}}
        for name,img,port in ((auth,AUTH_IMAGE,9999),(rest,REST_IMAGE,3000)):
            env_path=stage/(name+'.env');env_path.write_text('\n'.join(k+'='+v for k,v in configs[name].items())+'\n');env_files.append(env_path)
            service_id=run(['docker','create','--name',name,'--network='+network,'--network-alias='+('auth' if name==auth else 'rest'),'--log-driver=none','--label','sko-purpose=common-http-rehearsal','--env-file',str(env_path),img]).decode().strip()
            check(re.fullmatch(r'[a-f0-9]{64}',service_id) is not None,'service_container_id_invalid')
            containers.append(service_id)
            captures['auth' if name==auth else 'rest']=StartupCapture(['docker','start','-a',name],env)
        state['phase']='internal_curl_probe'
        tools=run(['docker','exec',db,'/bin/sh','-c','command -v curl >/dev/null 2>&1 && printf available']).decode()
        check(tools=='available','internal_curl_missing')
        endpoints={}
        for label,name,port,img in (('auth',auth,9999,AUTH_IMAGE),('rest',rest,3000,REST_IMAGE)):
            state['phase']=label+'_endpoint_inspect'
            for attempt in range(50):
                info=json.loads(run(['docker','inspect',name]))[0]
                if info.get('State',{}).get('Status') in ('running','exited','dead'):break
                time.sleep(.1)
            state[label+'_startup']=safe_service_state(info)
            endpoints[label]=internal_endpoint(info,port,network,subnet,img)
        http=ExpenseHttp(db,endpoints,env)
        state['phase']='auth_health_wait'
        for _ in range(90):
            try:
                if http.call('auth','/health',method='GET')[0]==200: break
            except (OSError,RuntimeError): pass
            time.sleep(1)
        else: raise RuntimeError('auth_not_ready')
        state['phase']='synthetic_gotrue_users';service=jwt(secret,'service_role');actors={};tokens={};sessions={}
        for label in ('admin','viewer','other_admin','outsider'):
            password='Synthetic-'+secrets.token_hex(24)+'!A1';email='sko-http-'+label+'-'+suffix+'@example.invalid'
            status,created=http.call('auth','/admin/users',service,{'email':email,'password':password,'email_confirm':True})
            check(status==200 and isinstance(created,dict) and isinstance(created.get('id'),str),'synthetic_user_create_failed')
            actor=str(uuid.UUID(created['id']));actors[label]=actor
            status,logged=http.call('auth','/token?grant_type=password',body={'email':email,'password':password})
            check(status==200 and isinstance(logged,dict) and logged.get('user',{}).get('id')==actor and isinstance(logged.get('access_token'),str),'gotrue_login_failed')
            tokens[label]=logged['access_token']
            claims=json.loads(base64.urlsafe_b64decode(tokens[label].split('.')[1]+'==='))
            check(claims.get('sub')==actor and claims.get('role')=='authenticated' and isinstance(claims.get('session_id'),str),'gotrue_claims_invalid')
            sessions[label]=str(uuid.UUID(claims['session_id']))
            check(value("SELECT EXISTS(SELECT 1 FROM auth.sessions WHERE id='"+sessions[label]+"' AND user_id='"+actor+"');")=='t','gotrue_session_not_persisted')
        cid=scope['company_id'];doc=scope['document_id']
        query("INSERT INTO public.company_members(company_id,user_id,role) VALUES('"+cid+"','"+actors['admin']+"','admin');")
        check(value("SELECT EXISTS(SELECT 1 FROM public.company_members WHERE company_id='"+cid+"' AND user_id='"+actors['admin']+"' AND role::text='admin') AND EXISTS(SELECT 1 FROM auth.sessions WHERE id='"+sessions['admin']+"' AND user_id='"+actors['admin']+"');")=='t','synthetic_admin_scope_invalid')
        state['phase']='private_conversion_with_gotrue_actor_context'
        conversion=conversion_for_actor(bundle,actors['admin'],sessions['admin'])
        query('BEGIN;\n'+bundle['files']['conversion.sql']+'\n'+conversion+'\n'+bundle['files']['negotiation.sql']+'\nCOMMIT;')
        state['clone_changes_committed']=True
        state['private_conversion_verified']=True
        state['phase']='http_directional_read_boundary'
        body={'p_document_kind':'paymentCertificate','p_document_id':doc}
        detail_body={'p_certificate_id':doc}
        # Resolve the pinned restored RPC argument names; never guess a new public RPC.
        arg_rows=json.loads(value("SELECT jsonb_object_agg(proname,to_jsonb(proargnames)) FROM pg_proc WHERE oid IN ('public.read_expense_document(text,uuid)'::regprocedure,'public.payment_certificate_detail_rows(uuid)'::regprocedure);"))
        check(len(arg_rows['read_expense_document'])==2 and len(arg_rows['payment_certificate_detail_rows'])>=1,'rpc_arguments_changed')
        body=dict(zip(arg_rows['read_expense_document'],['paymentCertificate',doc]))
        detail_body={arg_rows['payment_certificate_detail_rows'][0]:doc}
        for _ in range(60):
            status,data=expense_rpc(http,'read_expense_document',tokens['admin'],body,True)
            if status==200:break
            check(status in (404,503),'supported_read_failed');time.sleep(.5)
        check(status==200 and isinstance(data,dict) and data.get('expense_cost_direction_v2',{}).get('amount_yen')==1000,'supported_directional_snapshot_invalid')
        status,detail=expense_rpc(http,'payment_certificate_detail_rows',tokens['admin'],detail_body,True)
        check(status==200 and isinstance(detail,list),'supported_detail_failed')
        path='/payment_certificates?id=eq.'+doc+'&select=id,gross_amount,deductions,net_amount'
        status,rows=http.call('rest',path,tokens['admin'],method='GET',headers={'x-sko-payment-source-version':'2'})
        check(status==200 and len(rows)==1 and rows[0]['gross_amount']==0 and rows[0]['deductions']==1000 and rows[0]['net_amount']==-1000,'supported_exact_totals_invalid')
        for name,params in [('read_expense_document',body),('payment_certificate_detail_rows',detail_body)]:
            status,_=expense_rpc(http,name,tokens['admin'],params,False);check(status in (401,403),'legacy_rpc_allowed')
            for token in (None,tokens['outsider']):
                status,data=expense_rpc(http,name,token,params,True)
                check(status in (401,403) or (status==200 and (data is None or data==[])),'unrelated_actor_rpc_leak')
        status,rows=http.call('rest',path,tokens['admin'],method='GET');check(status in (401,403) or (status==200 and rows==[]),'legacy_direct_table_allowed')
        status,rows=http.call('rest',path,tokens['outsider'],method='GET',headers={'x-sko-payment-source-version':'2'});check(status in (401,403) or (status==200 and rows==[]),'outsider_direct_table_allowed')
        corrupt=tokens['admin'].split('.');corrupt[2]=('A' if corrupt[2][0]!='A' else 'B')+corrupt[2][1:]
        status,_=expense_rpc(http,'read_expense_document','.'.join(corrupt),body,True);check(status==401,'invalid_jwt_signature_allowed')
        state.update(gotrue_issued_jwt_verified=True,private_conversion_sql_not_http_mutation=True,
            directional_http_read_verified=True,supported_header_verified=True,legacy_header_denial=True,outsider_denial=True,
            same_retry_audit_settlement_verified=True,invalid_signature_denial=True)
        state['phase']='original_identity_preservation'
        check(identity_fingerprint(list(actors.values()))==original_identity,'original_owner_identity_company_roles_changed')
        final_source=json.loads(run(['docker','inspect',original_name]))[0]
        check(not final_source['State']['Running'] and final_source['HostConfig']['NetworkMode']=='none' and not final_source['HostConfig'].get('PortBindings') and final_source['Config']['Image']==common.transport.BASE_IMAGE,'original_restore_changed')
        state.update(verified=True,phase='verified',http_transport='docker_exec_internal_curl_no_host_ports',original_identity_preserved=True)
        code=0
    except (Exception,KeyboardInterrupt) as error:
        if isinstance(error,HttpExecFailure):state['http_client_exitcode']=error.client_returncode
        if isinstance(error,RuntimeError) and error.args and isinstance(error.args[0],str) and re.fullmatch(r'[a-z_]{1,80}',error.args[0]):
            state['failure_code']=error.args[0]
        state['verified']=False;code=1
    finally:
        cleanup_ok=True
        for label,capture in captures.items():
            state[label+'_startup_diagnostic']=capture.summary()
        # Stop/remove only containers created by this invocation; no original name is in this list.
        for name in reversed(containers):
            try:
                result=subprocess.run(['docker','rm','-f',name],stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=30)
                cleanup_ok=cleanup_ok and result.returncode==0
            except (Exception,KeyboardInterrupt): cleanup_ok=False
        if network_id and re.fullmatch(r'[a-f0-9]{64}',network_id):
            try:
                result=subprocess.run(['docker','network','rm',network_id],stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=30)
                cleanup_ok=cleanup_ok and result.returncode==0
            except (Exception,KeyboardInterrupt): cleanup_ok=False
        for label,capture in captures.items():
            try:
                capture.close();state[label+'_startup_diagnostic']=capture.summary()
            except Exception:cleanup_ok=False
        for path in env_files:
            try: path.unlink(missing_ok=True)
            except OSError: cleanup_ok=False
        state['cleanup_verified']=cleanup_ok
        if not cleanup_ok: state['verified']=False;code=1
        if stage: (stage/'http-rehearsal-status.json').write_text(json.dumps(state,ensure_ascii=False,indent=2))
    result=('隔離cloneの既存private変換とGoTrue発行JWTのHTTP読取境界、旧要求/他actor拒否、−1000円/再実行/監査/精算履歴保持を確認: '+stage.name+'。本番適用・実Google/電話・実機配布は未実施。') if state.get('verified') else ('経費HTTP/JWT検証は未完了（段階: '+state.get('phase','準備')+'）。元の復元DB・バックアップ・本番は変更していません。')
    print(result,flush=True)
    if sys.platform=='darwin': subprocess.run(['/usr/bin/pbcopy'],input=result,text=True,check=False)
    return code


if __name__=='__main__': sys.exit(main())
