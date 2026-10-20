#!/usr/bin/env python3
"""Read only an existing stopped failed rehearsal clone; never install or change guards."""
import hashlib,json,os,re,subprocess,sys,tempfile,time
from pathlib import Path
CAPTURE_SHA256='62f967ee0b5861382caf3f7605c60a39b2b9223a0d8fc32576471029a44994d1'
SAFE_VALUES={'owner','volatility','parallel','strict','leakproof','definer','acl','config','enabled','function','table','name','signature'}
def check(v,code):
    if not v:raise RuntimeError(code)
def private(p):check(not any(x.is_symlink() for x in (p,*p.parents)) and not p.stat().st_mode&0o077,'private_path_required')
def compare(actual,clone):
    result=[]
    check(set(actual)==set(clone)=={'functions','triggers','event_triggers'},'catalog_group_scope_differs')
    for kind,keys in [('functions',('signature',)),('triggers',('table','name')),('event_triggers',('name',))]:
        def index(rows):
            indexed={tuple(r[k] for k in keys):r for r in rows};check(len(indexed)==len(rows),'duplicate_catalog_identity');return indexed
        a,b=index(actual[kind]),index(clone[kind])
        for identity in sorted(set(a)|set(b)):
            if identity not in a or identity not in b:
                result.append({'kind':kind,'identity':list(identity),'scope':'production_only' if identity in a else 'clone_only'});continue
            fields=sorted(k for k in set(a[identity])|set(b[identity]) if k!='oid' and a[identity].get(k)!=b[identity].get(k))
            if fields:
                row={'kind':kind,'identity':list(identity),'differing_fields':fields}
                safe={k:{'production':a[identity].get(k),'clone':b[identity].get(k)} for k in fields if k in SAFE_VALUES}
                if safe:row['safe_metadata']=safe
                fingerprints={k:{'production_sha256':hashlib.sha256(str(a[identity].get(k)).encode()).hexdigest(),'clone_sha256':hashlib.sha256(str(b[identity].get(k)).encode()).hexdigest()} for k in fields if k in ('definition','source_md5')}
                if fingerprints:row['private_field_fingerprints']=fingerprints
                result.append(row)
    return result

def main():
    os.umask(0o077);stage=None;clone=None;started=False;code=1
    state={'schema':1,'verified':False,'read_only':True,'production_connected':False,'ddl_executed':False,'install_retried':False}
    try:
        check(sys.platform=='darwin','mac_required');check(not os.environ.get('DOCKER_HOST') and not os.environ.get('DOCKER_CONTEXT'),'docker_override_refused')
        runtime=Path(__file__).parent;p=runtime/'capture_queries.json';check(p.is_file() and not p.is_symlink() and hashlib.sha256(p.read_bytes()).hexdigest()==CAPTURE_SHA256,'capture_query_hash_changed');queries=json.loads(p.read_text())
        root=Path.home()/'SKO-source-backups';private(root)
        records=sorted([p for p in root.glob('expense-prepared-rehearsal-*') if p.is_dir() and not p.is_symlink()],key=lambda p:p.stat().st_mtime);check(records,'failed_rehearsal_required');source=records[-1];private(source)
        p=source/'rehearsal-status.json';private(p);saved=json.loads(p.read_text())
        check(saved.get('verified') is False and saved.get('phase')=='production_clone_contract_comparison' and saved.get('failure_code')=='catalog_non_oid_drift' and saved.get('container_stopped') is True and saved.get('install_commit_verified') is not True,'expected_preinstall_failed_state_required')
        clone=saved['container'];check(re.fullmatch(r'sko-expense-prepared-[a-f0-9]{12}',clone),'clone_name_invalid')
        p=source/'private-fresh-before.json';private(p);check(hashlib.sha256(p.read_bytes()).hexdigest()==saved['production_before_sha256'],'production_record_hash_changed');fresh=json.loads(p.read_text())
        original=root/'database-restore-01qyi5py';private(original);p=original/'rehearsal-status.json';private(p);origin=json.loads(p.read_text());original_name=origin['container'];check(re.fullmatch(r'sko-restore-[a-f0-9]{12}',original_name) and origin.get('container_stopped') and origin.get('archive_restore_verified'),'original_source_status_differs')
        stage=Path(tempfile.mkdtemp(prefix='expense-contract-readonly-',dir=root));state['phase']='local_clone_preflight';state['source_rehearsal']=source.name
        env={k:v for k,v in os.environ.items() if not k.startswith('PG') and k not in ('DB_PASSWORD','SUPABASE_DB_PASSWORD')}
        with (stage/'private-errors.log').open('xb') as errors:
            def run(args,data=None,timeout=60):
                r=subprocess.run(args,env=env,input=data,stdin=subprocess.DEVNULL if data is None else None,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=timeout)
                if r.stderr:errors.write(r.stderr);errors.flush()
                if r.returncode:
                    found=re.search(rb'(?:ERROR|FATAL):\s+([0-9A-Z]{5})(?:\s|$)',r.stderr)
                    if found:state['last_sqlstate']=found.group(1).decode()
                    raise RuntimeError('isolated_read_failed')
                return r.stdout
            context=json.loads(run(['docker','context','inspect']));check(context[0]['Endpoints']['docker']['Host'].startswith('unix://'),'remote_docker_refused')
            original_before=json.loads(run(['docker','inspect',original_name]))[0];check(not original_before['State']['Running'] and original_before['HostConfig']['NetworkMode']=='none' and not original_before['HostConfig'].get('PortBindings') and original_before['Config']['Labels'].get('sko-purpose')=='offline-restore','original_source_not_stopped_isolated')
            info=json.loads(run(['docker','inspect',clone]))[0];cmd=info['Config']['Cmd'];joined=' '.join(cmd)
            check(not info['State']['Running'] and info['HostConfig']['NetworkMode']=='none' and not info['HostConfig'].get('PortBindings') and info['Config']['Image']==saved['private_local_image'] and info['Config']['Labels'].get('sko-purpose')=='expense-off-rehearsal' and all(s in joined for s in ('listen_addresses=','cron.launch_active_jobs=off','autovacuum=off','unix_socket_directories=/tmp')),'failed_clone_isolation_contract_differs')
            print('失敗した隔離コピーだけを起動し、カタログを読取専用で確認しています。導入は再実行しません。',flush=True)
            started=True;run(['docker','start',clone]);state['phase']='clone_read_only_capture'
            for _ in range(30):
                r=subprocess.run(['docker','exec',clone,'pg_isready','-h','/tmp','-U','postgres'],env=env,stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=errors,timeout=5)
                if r.returncode==0:break
                time.sleep(1)
            else:raise RuntimeError('clone_not_ready')
            sql="BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;SET LOCAL statement_timeout='30s';SET LOCAL lock_timeout='3s';SELECT jsonb_build_object('readonly',current_setting('transaction_read_only'),'cron_off',current_setting('cron.launch_active_jobs')='off','autovacuum_off',current_setting('autovacuum')='off','listen_local',current_setting('listen_addresses')='','database_match',current_database()='postgres' AND current_user='postgres','catalog',("+queries['catalogSql']+"));COMMIT;"
            output=run(['docker','exec','-i','-e','PGOPTIONS=-c default_transaction_read_only=on',clone,'psql','-X','-w','-h','/tmp','-U','postgres','-d','postgres','-q','-A','-t','-v','ON_ERROR_STOP=1','-v','VERBOSITY=sqlstate'],sql.encode()).decode().strip();record=json.loads(output.splitlines()[-1])
            check(record['readonly']=='on' and all(record[k] for k in ('cron_off','autovacuum_off','listen_local','database_match')),'readonly_server_contract_differs')
            (stage/'private-clone-expense-catalog.json').write_text(json.dumps(record,ensure_ascii=False,indent=2));diff=compare(fresh['before'],record['catalog']);(stage/'safe-catalog-difference.json').write_text(json.dumps(diff,ensure_ascii=False,indent=2));state.update(verified=True,phase='verified',difference_count=len(diff));code=0
            original_after=json.loads(run(['docker','inspect',original_name]))[0];check(not original_after['State']['Running'] and original_after['State']['StartedAt']==original_before['State']['StartedAt'] and original_after['State']['FinishedAt']==original_before['State']['FinishedAt'] and original_after['Config']==original_before['Config'] and original_after['HostConfig']==original_before['HostConfig'],'original_source_state_changed')
    except (Exception,KeyboardInterrupt) as error:
        state['verified']=False;code=1
        if isinstance(error,RuntimeError) and error.args and re.fullmatch(r'[a-z_]{1,90}',str(error.args[0])):state['failure_code']=error.args[0]
    finally:
        if started:
            try:state['container_stopped']=subprocess.run(['docker','stop','-t','10',clone],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=30).returncode==0
            except (Exception,KeyboardInterrupt):state['container_stopped']=False
            if not state['container_stopped']:state['verified']=False;code=1
        if stage:(stage/'diagnostic-status.json').write_text(json.dumps(state,ensure_ascii=False,indent=2))
    result=('隔離コピーの読取専用カタログ差分: '+json.dumps(diff,ensure_ascii=False,separators=(',',':'))+'。' if state['verified'] else '隔離カタログ読取は未完了（'+state.get('failure_code','private_log_review_required')+'）。')+'本番接続・導入再実行・DB変更なし。'
    print(result,flush=True)
    if sys.platform=='darwin':subprocess.run(['/usr/bin/pbcopy'],input=result,text=True,check=False)
    return code
if __name__=='__main__':sys.exit(main())
