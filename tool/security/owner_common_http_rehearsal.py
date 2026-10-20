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
import owner_payroll_common_rehearsal as common

AUTH_IMAGE='supabase/gotrue@sha256:1736a63078f5922b198c4cbe50f80ab9a2d3b54fe8b7b6cfb2e9dc5dbbc12c6b'
REST_IMAGE='postgrest/postgrest@sha256:d155c6718ed9a9f990d159a2ab7c0a3f16944dbb6d0a0344557421042acfe0df'
PAYROLL_HASH='acdb78113fd628c32411c8ce73086213'


def check(value,code):
    if not value: raise RuntimeError(code)


def jwt(secret,role):
    enc=lambda value:base64.urlsafe_b64encode(json.dumps(value,separators=(',',':')).encode()).decode().rstrip('=')
    now=int(time.time()); unsigned=enc({'alg':'HS256','typ':'JWT'})+'.'+enc({'role':role,'aud':'authenticated','iat':now,'exp':now+3600,'iss':'supabase'})
    return unsigned+'.'+base64.urlsafe_b64encode(hmac.new(secret.encode(),unsigned.encode(),hashlib.sha256).digest()).decode().rstrip('=')


class HttpExecFailure(RuntimeError):
    def __init__(self,code):
        super().__init__('internal_http_client_failed')
        self.client_returncode=code


def bounded_http_exec(args,data,env,timeout=30):
    check(isinstance(data,bytes) and len(data)<=65536,'http_request_too_large')
    proc=subprocess.Popen(args,env=env,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL)
    selector=selectors.DefaultSelector(); output=bytearray(); offset=0; deadline=time.monotonic()+timeout
    try:
        os.set_blocking(proc.stdin.fileno(),False);os.set_blocking(proc.stdout.fileno(),False)
        selector.register(proc.stdin,selectors.EVENT_WRITE)
        selector.register(proc.stdout,selectors.EVENT_READ)
        while selector.get_map():
            remaining=deadline-time.monotonic()
            check(remaining>0,'internal_http_timeout')
            for key,_ in selector.select(min(remaining,1)):
                if key.fileobj is proc.stdin:
                    try: sent=os.write(proc.stdin.fileno(),data[offset:])
                    except BrokenPipeError: sent=0;offset=len(data)
                    offset+=sent
                    if offset>=len(data):selector.unregister(proc.stdin);proc.stdin.close()
                else:
                    chunk=os.read(proc.stdout.fileno(),16384)
                    if not chunk:selector.unregister(proc.stdout);continue
                    output.extend(chunk)
                    check(len(output)<=1048584,'http_response_too_large')
        code=proc.wait(timeout=max(.1,deadline-time.monotonic()))
        if code:raise HttpExecFailure(code)
        return bytes(output)
    finally:
        selector.close()
        if proc.poll() is None:
            proc.kill()
            try:proc.wait(timeout=5)
            except subprocess.TimeoutExpired:pass
        for stream in (proc.stdin,proc.stdout):
            if stream and not stream.closed:stream.close()


class InternalCurlHttp:
    def __init__(self,db_container,endpoints,env):
        check(re.fullmatch(r'sko-http-db-[a-f0-9]{12}',db_container) is not None,'http_container_invalid')
        check(set(endpoints)=={'auth','rest'},'http_services_invalid')
        for endpoint in endpoints.values():
            check(re.fullmatch(r'http://[0-9.]+:[0-9]{1,5}',endpoint) is not None,'internal_endpoint_invalid')
            host=endpoint.removeprefix('http://').split(':')[0]
            check(ipaddress.ip_address(host).version==4 and ipaddress.ip_address(host).is_private,'private_ipv4_endpoint_required')
        self.db_container=db_container;self.endpoints=endpoints;self.env=env

    def config(self,service,path,token,body,method,headers):
        check(service in self.endpoints and isinstance(path,str) and path.startswith('/') and not path.startswith('//') and not any(c in path for c in ('\r','\n')),'internal_route_invalid')
        check(method in ('GET','POST','PUT','DELETE'),'http_method_invalid')
        lines=['url = '+json.dumps(self.endpoints[service]+path),'request = '+json.dumps(method), 'header = "Accept: application/json"']
        if token:
            check(isinstance(token,str) and re.fullmatch(r'[A-Za-z0-9_.-]+',token) is not None,'http_token_invalid')
            lines.append('header = '+json.dumps('Authorization: Bearer '+token))
        for key,value in (headers or {}).items():
            check(key in ('Accept-Profile','Content-Profile') and isinstance(value,str) and re.fullmatch(r'[a-z_]+',value) is not None,'http_header_invalid')
            lines.append('header = '+json.dumps(key+': '+value))
        if body is not None:
            lines.append('header = "Content-Type: application/json"')
            lines.append('data-binary = '+json.dumps(json.dumps(body,ensure_ascii=False,separators=(',',':')),ensure_ascii=False))
        data=('\n'.join(lines)+'\n').encode()
        check(len(data)<=65536,'http_request_too_large')
        return data

    def call(self,service,path,token=None,body=None,method='POST',headers=None):
        data=self.config(service,path,token,body,method,headers)
        args=['docker','exec','-i',self.db_container,'curl','--disable','--silent','--show-error','--noproxy','*','--proxy','','--connect-timeout','5','--max-time','20','--max-redirs','0','--proto','=http','--max-filesize','1048576','--write-out','\n%{http_code}','--config','-']
        raw=bounded_http_exec(args,data,self.env)
        body_raw,separator,status_raw=raw.rpartition(b'\n')
        check(separator==b'\n' and re.fullmatch(rb'[0-9]{3}',status_raw) is not None,'http_status_missing')
        status=int(status_raw)
        check(not 300<=status<400,'http_redirect_refused')
        check(len(body_raw)<=1048576,'http_response_too_large')
        try:value=json.loads(body_raw) if body_raw else None
        except (ValueError,UnicodeDecodeError):value=None
        return status,value


def rpc(http,name,token,body):
    check(re.fullmatch(r'[a-z_]+',name) is not None,'rpc_name_invalid')
    return http.call('rest','/rpc/'+name,token,body)


def commit_install(bundle):
    sql=common.build_install(bundle)
    check(sql.endswith('\nROLLBACK;'),'install_transaction_shape_changed')
    # HTTP calls use separate connections. Commit ONLY in the new disposable clone.
    return sql.removesuffix('\nROLLBACK;')+'\nCOMMIT;'


def clone_command(name,image,network):
    args=common.transport.clone_command(name,image)
    args[1]='create';args.remove('-d')
    args[args.index('--network=none')]='--network='+network
    args.insert(args.index('--user=postgres'),'--network-alias=db')
    args[args.index('sko-purpose=expense-off-rehearsal')]='sko-purpose=common-http-rehearsal'
    args[args.index('listen_addresses=')]='listen_addresses=*'
    args[args.index('--no-healthcheck'):args.index('--no-healthcheck')]=['--log-driver=none']
    args += ['-c','hba_file=/tmp/sko-http-hba.conf','-c','log_statement=none','-c','log_min_error_statement=panic','-c','logging_collector=off']
    return args


def image_check(info,expected):
    check(expected in info.get('RepoDigests',[]),'required_image_digest_missing')
    check(info.get('Os')=='linux' and info.get('Architecture') in ('arm64','amd64'),'image_platform_invalid')


def internal_endpoint(info,port,network,subnet,expected_image):
    check(set(info['NetworkSettings']['Networks'])=={network},'service_network_invalid')
    check(info['HostConfig'].get('LogConfig',{}).get('Type')=='none','service_logs_not_disabled')
    check(not info['HostConfig'].get('PortBindings'),'host_publish_forbidden')
    check(info['State']['Running'] and info['Config']['Image']==expected_image,'service_not_running')
    host=info['NetworkSettings']['Networks'][network].get('IPAddress','')
    ip=ipaddress.ip_address(host)
    check(ip.version==4 and ip in subnet and ip.is_private and not ip.is_loopback,'service_ip_not_internal')
    return 'http://'+str(ip)+':'+str(port)


def identity_sql(excluded):
    skip=','.join("'"+str(uuid.UUID(v))+"'" for v in excluded) or "'00000000-0000-0000-0000-000000000000'"
    return "SELECT md5(jsonb_build_object('users',(SELECT jsonb_agg(jsonb_build_object('id',id,'email',email,'phone',phone,'password',encrypted_password,'app',raw_app_meta_data,'metadata',raw_user_meta_data) ORDER BY id) FROM auth.users WHERE id NOT IN ("+skip+")), 'identities',(SELECT jsonb_agg(jsonb_build_object('user_id',user_id,'provider',provider,'provider_id',provider_id,'data',identity_data) ORDER BY user_id,provider) FROM auth.identities WHERE user_id NOT IN ("+skip+")), 'members',(SELECT jsonb_agg(to_jsonb(m) ORDER BY to_jsonb(m)::text) FROM public.company_members m WHERE user_id NOT IN ("+skip+")), 'companies',(SELECT jsonb_agg(to_jsonb(c) ORDER BY id) FROM public.companies c))::text);"


def auth_database_url(login,password):
    check(re.fullmatch(r'sko_http_auth_[a-f0-9]{12}',login) is not None,'auth_db_login_invalid')
    check(re.fullmatch(r'[a-f0-9]{64}',password) is not None,'auth_db_password_shape_invalid')
    return 'postgres://'+login+':'+password+'@db:5432/postgres?'+urlencode({'options':'-c role=supabase_auth_admin -c search_path=auth'})


def auth_scope_sql():
    return "SET ROLE supabase_auth_admin;SET search_path=auth;SELECT jsonb_build_object('auth_current_role',current_user='supabase_auth_admin','auth_current_schema',current_schema()='auth','auth_usage',has_schema_privilege(current_user,'auth','USAGE'),'auth_create',has_schema_privilege(current_user,'auth','CREATE'),'auth_schema_owner',pg_has_role(current_user,(SELECT nspowner FROM pg_namespace WHERE nspname='auth'),'USAGE'),'migration_table_found',to_regclass('schema_migrations') IS NOT NULL,'migration_table_select',has_table_privilege(current_user,'auth.schema_migrations','SELECT'),'migration_table_insert',has_table_privilege(current_user,'auth.schema_migrations','INSERT'),'auth_users_select',has_table_privilege(current_user,'auth.users','SELECT'),'auth_users_insert',has_table_privilege(current_user,'auth.users','INSERT'));"


class StartupCapture:
    """Drain attached service output; retain only fixed anonymous classifications."""
    RULES={'db_authentication_failed':b'password authentication failed','db_permission_denied':b'permission denied','db_owner_required':b'must be owner','db_connection_refused':b'connection refused','db_name_resolution_failed':b'no such host','migration_failure':b'migrat','configuration_failure':b'config','required_setting_missing':b'required','db_object_missing':b'does not exist','address_bind_failure':b'address already in use','db_ssl_failure':b'ssl','schema_auth_denied':b'permission denied for schema auth','schema_public_denied':b'permission denied for schema public','migration_table_mentioned':b'schema_migrations','create_schema_operation':b'create schema','create_table_operation':b'create table','table_auth_users_denied':b'permission denied for table users','invalid_log_level':b'invalid log level'}
    def __init__(self,args,env):
        self.flags=set();self.sqlstates=set();self.lock=threading.Lock()
        self.proc=subprocess.Popen(args,env=env,stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        self.thread=threading.Thread(target=self.read,daemon=True);self.thread.start()
    def read(self):
        tail=b''
        try:
            while True:
                chunk=os.read(self.proc.stdout.fileno(),4096)
                if not chunk:break
                tail=(tail+chunk)[-8192:];lower=tail.lower()
                with self.lock:
                    for code,needle in self.RULES.items():
                        if needle in lower:self.flags.add(code)
                    for code in re.findall(rb'SQLSTATE[ :]+([0-9A-Z]{5})',tail):self.sqlstates.add(code.decode())
        except (OSError,ValueError):pass
    def summary(self):
        with self.lock:return {'categories':sorted(self.flags),'sqlstates':sorted(self.sqlstates)}
    def close(self):
        if self.proc.poll() is None:self.proc.terminate()
        try:self.proc.wait(timeout=5)
        except subprocess.TimeoutExpired:self.proc.kill();self.proc.wait(timeout=5)
        self.thread.join(timeout=5)
        if not self.thread.is_alive():self.proc.stdout.close()


def safe_service_state(info):
    value=info.get('State',{})
    return {'running':value.get('Running') is True,'exit_code':value.get('ExitCode') if type(value.get('ExitCode')) is int else None,'oom_killed':value.get('OOMKilled') is True}


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
        bundle=json.loads((Path(__file__).parent/'common_payroll_sources.json').read_text())
        install=commit_install(bundle)
        stage=Path(tempfile.mkdtemp(prefix='common-http-rehearsal-',dir=root))
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
        state['phase']='install_common_clone_only';query(install);state['clone_changes_committed']=True
        scope_rows=json.loads(value("SELECT coalesce(jsonb_agg(jsonb_build_object('company_id',p.company_id,'worker_id',p.worker_id,'payroll_id',p.id,'month',p.period_start,'payroll_type',s.pay_type)),'[]'::jsonb) FROM public.payroll_statements p JOIN public.worker_payroll_settings s ON s.company_id=p.company_id AND s.worker_id=p.worker_id WHERE md5(to_jsonb(p)::text)='"+PAYROLL_HASH+"' AND p.automatic_calculation=true AND p.workflow_state='draft' AND p.period_start=date_trunc('month',current_timestamp AT TIME ZONE 'Asia/Tokyo')::date;"))
        check(len(scope_rows)==1,'protected_current_draft_required'); scope=scope_rows[0]
        for key in ('company_id','worker_id','payroll_id'): check(str(uuid.UUID(scope[key]))==scope[key],'scope_uuid_invalid')
        check(scope['payroll_type'] in ('daily','hourly','monthly'),'payroll_type_invalid')
        def identity_fingerprint(excluded): return value(identity_sql(excluded))
        original_identity=identity_fingerprint([])
        pw_auth=secrets.token_hex(32);pw_rest=secrets.token_hex(32);secret=secrets.token_hex(48)
        state['phase']='synthetic_database_roles'
        query("SET password_encryption='scram-sha-256';CREATE ROLE "+db_auth+" LOGIN INHERIT PASSWORD '"+pw_auth+"';GRANT supabase_auth_admin TO "+db_auth+";CREATE ROLE "+db_rest+" LOGIN NOINHERIT PASSWORD '"+pw_rest+"';GRANT anon,authenticated,service_role TO "+db_rest+";GRANT CONNECT ON DATABASE postgres TO "+db_auth+','+db_rest+';',role='supabase_admin')
        state['phase']='auth_role_scope_preflight'
        state['auth_role_scope']=json.loads(query(auth_scope_sql(),role=db_auth).splitlines()[-1])
        check(all(state['auth_role_scope'].values()),'auth_role_scope_preflight_failed')
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
        http=InternalCurlHttp(db,endpoints,env)
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
        cid=scope['company_id']; read_body={'p_company_id':cid}
        for label,role in (('admin','admin'),('viewer','viewer'),('other_admin','admin')):
            query("INSERT INTO public.company_members(company_id,user_id,role) VALUES('"+cid+"','"+actors[label]+"','"+role+"');")
        state['phase']='http_read_and_authorization'
        snapshot=None
        for _ in range(60):
            status,data=rpc(http,'read_company_common_allowances_admin',tokens['admin'],read_body)
            if status==200: snapshot=data;break
            check(status in (404,503),'admin_common_read_failed');time.sleep(.5)
        check(isinstance(snapshot,dict) and snapshot.get('company_id')==cid and snapshot.get('can_edit') is True,'admin_snapshot_invalid')
        status,view=rpc(http,'read_company_common_allowances_admin',tokens['viewer'],read_body)
        check(status==200 and view.get('can_edit') is False,'viewer_common_read_failed')
        for token in (None,tokens['outsider']):
            status,_=rpc(http,'read_company_common_allowances_admin',token,read_body);check(status in (401,403),'unrelated_actor_common_read_allowed')
        for token in (tokens['admin'],tokens['outsider']):
            status,rows=http.call('rest','/payroll_statements?id=eq.'+scope['payroll_id']+'&select=id',token,method='GET')
            if token==tokens['admin']: check(status==200 and isinstance(rows,list) and len(rows)==1,'admin_payroll_rls_denied')
            else: check(status in (401,403) or (status==200 and rows==[]),'unrelated_actor_payroll_rls_allowed')
        corrupt=tokens['admin'].split('.')
        corrupt[2]=('A' if corrupt[2][0]!='A' else 'B')+corrupt[2][1:]
        status,_=rpc(http,'read_company_common_allowances_admin','.'.join(corrupt),read_body);check(status==401,'invalid_jwt_signature_allowed')
        legacy=[{key:item.get(key) for key in ('slot','id','generation','name','source_unit','amount_yen')} for item in snapshot['legacy_refs']]
        save_body={'p_company_id':cid,'p_payroll_type':scope['payroll_type'],'p_expected_version':snapshot['version'],'p_expected_source':snapshot['expected_source'],'p_request_id':str(uuid.uuid4()),'p_items':[{'id':None,'client_key':'http-earning','section':'earning','unit':'month','name':'隔離HTTP共通支給','amount_yen':1000},{'id':None,'client_key':'http-deduction','section':'deduction','unit':'month','name':'隔離HTTP共通控除','amount_yen':250}],'p_legacy_slots':legacy,'p_confirm_adoption':True}
        for token in (None,tokens['viewer'],tokens['outsider']):
            status,_=rpc(http,'save_company_common_allowances',token,save_body);check(status in (401,403),'unauthorized_common_save_allowed')
        state['phase']='http_save_retry_cas'
        status,saved=rpc(http,'save_company_common_allowances',tokens['admin'],save_body);check(status==200 and isinstance(saved,dict),'http_common_save_failed')
        status,repeated=rpc(http,'save_company_common_allowances',tokens['admin'],save_body);check(status==200 and repeated==saved,'http_save_retry_changed_receipt')
        stale={**save_body,'p_request_id':str(uuid.uuid4())};status,failure=rpc(http,'save_company_common_allowances',tokens['admin'],stale)
        check(status>=400 and isinstance(failure,dict) and failure.get('code')=='40001','http_save_stale_source_allowed')
        receipt_body={'p_company_id':cid,'p_request_id':save_body['p_request_id']}
        status,receipt=rpc(http,'read_company_common_allowance_request',tokens['admin'],receipt_body);check(status==200 and receipt.get('found') is True and receipt.get('actor_id')==actors['admin'],'actor_receipt_invalid')
        status,other_receipt=rpc(http,'read_company_common_allowance_request',tokens['other_admin'],receipt_body);check(status==200 and other_receipt.get('found') is False,'receipt_leaked_to_another_actor')
        state['phase']='http_publish_retry_cas'
        query("INSERT INTO company_common_allowance_private.payroll_activation VALUES('"+cid+"','"+scope['month']+"');")
        status,publication=rpc(http,'read_company_common_payroll_publications',tokens['admin'],read_body);check(status==200 and isinstance(publication,dict),'publication_read_failed')
        publish_body={'p_company_id':cid,'p_payroll_type':scope['payroll_type'],'p_starts_on':scope['month'],'p_common_version':publication['common_version'],'p_common_source':publication['common_source'],'p_timeline_version':publication['timeline_version'],'p_request_id':str(uuid.uuid4())}
        for token in (None,tokens['viewer'],tokens['outsider']):
            status,_=rpc(http,'publish_company_common_payroll',token,publish_body);check(status in (401,403),'unauthorized_publication_allowed')
        status,published=rpc(http,'publish_company_common_payroll',tokens['admin'],publish_body);check(status==200 and isinstance(published,dict),'http_publication_failed')
        status,repeated=rpc(http,'publish_company_common_payroll',tokens['admin'],publish_body);check(status==200 and repeated==published,'http_publish_retry_changed_receipt')
        stale={**publish_body,'p_request_id':str(uuid.uuid4())};status,failure=rpc(http,'publish_company_common_payroll',tokens['admin'],stale)
        check(status>=400 and isinstance(failure,dict) and failure.get('code')=='40001','http_stale_publication_allowed')
        state['phase']='http_session_expiry'
        query("UPDATE auth.sessions SET not_after=clock_timestamp()-interval '1 second' WHERE id='"+sessions['admin']+"' AND user_id='"+actors['admin']+"';")
        for name,body in (('read_company_common_allowances_admin',read_body),('save_company_common_allowances',save_body),('publish_company_common_payroll',publish_body)):
            status,failure=rpc(http,name,tokens['admin'],body)
            check(status in (401,403) and isinstance(failure,dict),'expired_session_rpc_allowed')
        state['phase']='http_logout_old_jwt'
        status,_=http.call('auth','/logout?scope=local',tokens['other_admin'],body={});check(status in (200,204),'local_logout_failed')
        status,_=rpc(http,'read_company_common_allowances_admin',tokens['other_admin'],read_body);check(status in (401,403),'logged_out_session_rpc_allowed')
        state['phase']='original_identity_preservation'
        check(identity_fingerprint(list(actors.values()))==original_identity,'original_owner_identity_company_roles_changed')
        final_source=json.loads(run(['docker','inspect',original_name]))[0]
        check(not final_source['State']['Running'] and final_source['HostConfig']['NetworkMode']=='none' and not final_source['HostConfig'].get('PortBindings') and final_source['Config']['Image']==common.transport.BASE_IMAGE,'original_restore_changed')
        state.update(verified=True,phase='verified',http_transport='docker_exec_internal_curl_no_host_ports',gotrue_issued_jwt_verified=True,invalid_signature_denial=True,direct_payroll_rls_verified=True,live_auth_session_verified=True,http_admin_read_save_publish=True,viewer_read_write_denial=True,unrelated_actor_denial=True,actor_receipt_isolation=True,save_retry_cas=True,publish_retry_cas=True,expired_session_denial=True,logout_old_jwt_denial=True,original_identity_preserved=True)
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
    result=('隔離実DBと実GoTrue発行JWTで共通手当のHTTP読取・保存・公開、権限/Actor境界、再試行/CAS、session期限切れ・ログアウト後旧JWT拒否、原本identity保持を確認: '+stage.name+'。本番適用・実Google/電話・実機配布は未実施。') if state.get('verified') else ('共通手当HTTP/JWT検証は未完了（段階: '+state.get('phase','準備')+'）。元の復元DB・バックアップ・本番は変更していません。')
    print(result,flush=True)
    if sys.platform=='darwin': subprocess.run(['/usr/bin/pbcopy'],input=result,text=True,check=False)
    return code


if __name__=='__main__': sys.exit(main())
