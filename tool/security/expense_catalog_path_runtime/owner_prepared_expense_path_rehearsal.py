#!/usr/bin/env python3
"""Offline clone rehearsal with explicit catalog display path and physical event references."""
import hashlib,json,os,re,shutil,subprocess,sys,tempfile,time,uuid
from pathlib import Path
import owner_expense_off_rehearsal as base
import owner_collector_public_create_rehearsal as probes

def check(v,code):
    if not v:raise RuntimeError(code)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def private(p):
    check(not any(x.is_symlink() for x in (p,*p.parents)) and not p.stat().st_mode&0o077,'private_path_required')
def map_catalog(actual,local):
    check(set(actual)==set(local)=={'functions','triggers','event_triggers'},'catalog_scope_differs')
    mapping={}
    for kind,keys in [('functions',('signature',)),('triggers',('table','name')),('event_triggers',('name',))]:
        def index(rows):
            out={tuple(row[k] for k in keys):row for row in rows}
            check(len(out)==len(rows) and len({row['oid'] for row in rows})==len(rows),'catalog_identity_not_unique')
            return out
        a,b=index(actual[kind]),index(local[kind]);check(set(a)==set(b),'catalog_identity_scope_differs')
        mapping[kind]=[]
        for key in sorted(a):
            check({k:v for k,v in a[key].items() if k!='oid'}=={k:v for k,v in b[key].items() if k!='oid'},'catalog_non_oid_drift')
            mapping[kind].append({'identity':list(key),'production_oid':a[key]['oid'],'clone_oid':b[key]['oid']})
    return mapping


EVENT_REFERENCE_MD5={
 'extensions.set_graphql_placeholder()':'a2bc2d00b2cc2f5e8d2d6b8d73e2c360',
 'extensions.grant_pg_cron_access()':'3a3917aad6ddd66182bf45b7490c3029',
 'extensions.grant_pg_graphql_access()':'dd3f3e2bb94cff45ef24b9cecb6af1c8',
 'extensions.grant_pg_net_access()':'2ee4e6920eeba3068bcfa838105352e2',
 'extensions.pgrst_ddl_watch()':'7f27b8118fea5c88b0164331292859e3',
 'extensions.pgrst_drop_watch()':'bc09cc3003d66f91844af4cb05e203b7',
}
EVENT_REFERENCE_SQL="""SELECT coalesce(jsonb_agg(jsonb_build_object('event_name',e.evtname,'namespace',n.nspname,'proname',p.proname,'no_arguments',p.pronargs=0 AND p.proargtypes=''::oidvector,'signature',n.nspname||'.'||p.proname||'('||replace(oidvectortypes(p.proargtypes),', ',',')||')','source_md5',md5(p.prosrc)) ORDER BY e.evtname),'[]'::jsonb)::text FROM pg_event_trigger e JOIN pg_proc p ON p.oid=e.evtfoid JOIN pg_namespace n ON n.oid=p.pronamespace;"""
def verify_event_references(production,physical):
    expected={row['name']:row for row in production['event_triggers'] if row['function'] in EVENT_REFERENCE_MD5}
    check(len(expected)==6 and {r['function'] for r in expected.values()}==set(EVENT_REFERENCE_MD5),'production_event_reference_scope_differs')
    indexed={row['event_name']:row for row in physical};check(len(indexed)==len(physical),'physical_event_identity_not_unique')
    for name,row in expected.items():
        signature=row['function'];local=indexed.get(name)
        check(row['source_md5']==EVENT_REFERENCE_MD5[signature],'production_event_source_changed')
        check(local is not None and local['namespace']=='extensions' and local['signature']==signature and local['proname']==signature.removeprefix('extensions.').removesuffix('()') and local['no_arguments'] is True and local['source_md5']==EVENT_REFERENCE_MD5[signature],'physical_event_reference_differs')
    return [{'event_name':name,'signature':row['function'],'source_md5':row['source_md5']} for name,row in sorted(expected.items())]

def fixture_install(sql):
    check(sql.count('\nBEGIN;\n')==1 and sql.rstrip().endswith('COMMIT;'),'prepared_transaction_shape_changed')
    check('SET LOCAL ROLE postgres;' in sql,'prepared_role_guard_missing')
    return sql.replace('\nBEGIN;\n','\nBEGIN;\nGRANT CREATE ON SCHEMA public TO postgres;\n',1).rstrip().removesuffix('COMMIT;')+'RESET ROLE;\nREVOKE CREATE ON SCHEMA public FROM postgres;\nCOMMIT;'

CATALOG_SQL=probes.CATALOG_SQL
ROW_QUERIES_SQL=probes.ROW_QUERIES_SQL.replace("n.nspname in ('public','private','auth','storage','vault','cron')","n.nspname !~ '^pg_' and n.nspname<>'information_schema'")
SEQUENCE_QUERIES_SQL=probes.SEQUENCE_QUERIES_SQL.replace("n.nspname in ('public','private','auth','storage','vault','cron')","n.nspname !~ '^pg_' and n.nspname<>'information_schema'")
DEFAULT_ACL_SQL="SELECT coalesce(jsonb_agg(to_jsonb(d) ORDER BY oid),'[]'::jsonb)::text FROM pg_default_acl d;"

def main():
    os.umask(0o077);stage=None;clone=None;started=False;code=1
    state={'schema':1,'verified':False,'production_connected':False,'production_prepared_sql_executed':False,'clone_local_oid_mapping':True,'conversion_performed':False,'catalog_display_search_path':'public'}
    try:
        check(sys.platform=='darwin','mac_required');check(not os.environ.get('DOCKER_HOST') and not os.environ.get('DOCKER_CONTEXT'),'docker_override_refused')
        runtime=Path(__file__).parent;manifest=json.loads((runtime/'runtime_manifest.json').read_text())
        for name,expected in manifest['files'].items():
            p=runtime/name;check(p.is_file() and not p.is_symlink() and sha(p)==expected,'runtime_integrity_failed')
        root=Path.home()/'SKO-source-backups';private(root)
        candidates=sorted([p for p in root.glob('expense-prepare-only-*') if p.is_dir() and not p.is_symlink()],key=lambda p:p.stat().st_mtime)
        check(bool(candidates),'prepared_evidence_required');prepared=candidates[-1];private(prepared)
        statusfile=prepared/'prepare-status.json';private(statusfile);status=json.loads(statusfile.read_text())
        check(status.get('verified') is True and status.get('prepare_only') is True and status.get('production_connected') is False,'latest_prepare_not_verified')
        for name in ('private-prepared-install.sql.review-only','private-read-actual-after.sql.read-only'):
            p=prepared/name;private(p);check(p.is_file() and p.stat().st_size<16777216 and sha(p)==status['artifacts'][name]['sha256'],'prepared_artifact_integrity_failed')
        p=prepared/'private-fresh-before.json';private(p);check(p.stat().st_size<16777216 and sha(p)==status['source_checkpoint_sha256'],'fresh_record_integrity_failed');fresh=json.loads(p.read_text())
        check(fresh.get('schema')==1 and fresh.get('read_only')=='on' and fresh.get('exact_target_count')==1 and fresh.get('global_v2_or_basis_count')==0 and all(fresh.get(k) is False for k in ('converter_installed','conversion_audit_installed','rollout_installed')),'fresh_record_scope_differs')
        source=root/base.SOURCE;private(source);private(source/'rehearsal-status.json');original=json.loads((source/'rehearsal-status.json').read_text());check(original.get('archive_restore_verified') and original.get('container_stopped'),'verified_stopped_source_required')
        source_name=original['container'];check(re.fullmatch(r'sko-restore-[a-f0-9]{12}',source_name),'source_name_invalid')
        stage=Path(tempfile.mkdtemp(prefix='expense-prepared-rehearsal-',dir=root));state['phase']='immutable_evidence_copy'
        for name in ('private-prepared-install.sql.review-only','private-read-actual-after.sql.read-only','private-fresh-before.json'):shutil.copyfile(prepared/name,stage/name)
        for name in ('expense_default_off_plan.mjs','native_generator.mjs'):shutil.copyfile(runtime/name,stage/name)
        (stage/'source').mkdir(mode=0o700)
        for p in (runtime/'source').iterdir():shutil.copyfile(p,stage/'source'/p.name)
        state['source_prepared_directory']=prepared.name;state['production_before_sha256']=sha(stage/'private-fresh-before.json')
        env={k:v for k,v in os.environ.items() if not k.startswith('PG') and k not in ('DB_PASSWORD','SUPABASE_DB_PASSWORD')}
        with (stage/'private-errors.log').open('xb') as errors:
            def run(args,data=None,timeout=120):
                result=subprocess.run(args,env=env,input=data,stdin=subprocess.DEVNULL if data is None else None,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=timeout)
                if result.stderr:errors.write(result.stderr);errors.flush()
                if result.returncode:
                    found=re.search(rb'(?:ERROR|FATAL):\s+([0-9A-Z]{5})(?:\s|$)',result.stderr)
                    if found:state['last_sqlstate']=found.group(1).decode()
                    raise RuntimeError('isolated_subprocess_failed')
                return result.stdout
            context=json.loads(run(['docker','context','inspect']));check(context[0]['Endpoints']['docker']['Host'].startswith('unix://'),'remote_docker_refused')
            node=json.loads(run(['docker','image','inspect','node:22.21.0']))[0];node_id=node['Id'];check(re.fullmatch(r'sha256:[a-f0-9]{64}',node_id),'node_image_invalid')
            def generate():run(['docker','run','--rm','--network=none','--log-driver=none','--user',str(os.getuid())+':'+str(os.getgid()),'--mount','type=bind,source='+str(stage)+',target=/work','--workdir','/work',node_id,'node','native_generator.mjs'])
            generate();state['original_prepared_source_verified']=True
            src=json.loads(run(['docker','inspect',source_name]))[0]
            check(not src['State']['Running'] and src['HostConfig']['NetworkMode']=='none' and not src['HostConfig'].get('PortBindings') and src['Config']['Image']==base.BASE_IMAGE and src['Config']['Labels'].get('sko-purpose')=='offline-restore','source_container_mismatch')
            print('元の復元DBを停止したまま、通信なしの別コピーを作成しています。',flush=True)
            state['phase']='clone';image=run(['docker','commit',source_name],timeout=300).decode().strip();check(re.fullmatch(r'sha256:[a-f0-9]{64}',image),'clone_image_invalid')
            clone='sko-expense-prepared-'+uuid.uuid4().hex[:12];state['container']=clone;state['private_local_image']=image
            run(base.clone_command(clone,image)+['-c','autovacuum=off']);started=True
            for _ in range(60):
                if subprocess.run(['docker','exec',clone,'pg_isready','-h','/tmp','-U','postgres'],env=env,stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=errors,timeout=5).returncode==0:break
                time.sleep(1)
            else:raise RuntimeError('clone_not_ready')
            info=json.loads(run(['docker','inspect',clone]))[0];check(info['HostConfig']['NetworkMode']=='none' and not info['HostConfig'].get('PortBindings'),'clone_not_isolated')
            def query(sql,role='postgres'):return run(['docker','exec','-i',clone,'psql','-X','-w','-h','/tmp','-U',role,'-d','postgres','-q','-A','-t','-v','ON_ERROR_STOP=1','-v','VERBOSITY=sqlstate'],("SET search_path=public;SET statement_timeout='30s';SET lock_timeout='3s';\n"+sql).encode()).decode().strip()
            def value(sql):return query(sql).splitlines()[-1]
            check(value('SHOW cron.launch_active_jobs;')=='off','cron_not_disabled')
            state['phase']='clone_baseline'
            before_catalog=value(CATALOG_SQL);before_defaults=value(DEFAULT_ACL_SQL)
            rows=json.loads(value(ROW_QUERIES_SQL));check(rows,'business_tables_required');row_sql="SELECT jsonb_agg(to_jsonb(t) ORDER BY relation)::text FROM ("+' UNION ALL '.join(rows)+") t;";before_rows=value(row_sql)
            seqs=json.loads(value(SEQUENCE_QUERIES_SQL));seq_sql="SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY relation),'[]'::jsonb)::text FROM ("+' UNION ALL '.join(seqs)+") t;" if seqs else "SELECT '[]';";before_sequences=value(seq_sql)
            for name,data in [('private-clone-catalog-before.json',before_catalog),('private-clone-defaults-before.json',before_defaults),('private-clone-rowhashes-before.json',before_rows),('private-clone-sequences-before.json',before_sequences)]: (stage/name).write_text(data)
            capture_sql=json.loads((runtime/'capture_queries.json').read_text());state['phase']='physical_event_reference_preflight';physical=json.loads(value(EVENT_REFERENCE_SQL));proof=verify_event_references(fresh['before'],physical);(stage/'private-clone-event-reference-proof.json').write_text(json.dumps(proof,ensure_ascii=False,indent=2));state['physical_event_references_verified']=True;clone_before=json.loads(value(capture_sql['catalogSql']));clone_business=value(capture_sql['defaultOffBusinessHashSql'])
            print('本番記録と隔離コピーの金融hash・関数契約を照合しています。差があれば導入前に停止します。',flush=True)
            state['phase']='production_clone_contract_comparison';check(clone_business==fresh['business'],'clone_financial_hash_differs')
            mapping=map_catalog(fresh['before'],clone_before);(stage/'private-production-clone-oid-map.json').write_text(json.dumps(mapping,ensure_ascii=False,indent=2))
            local=dict(fresh,before=clone_before,business=clone_business,clone_local_fixture=True,production_before_sha256=state['production_before_sha256']);(stage/'private-clone-local-before.json').write_text(json.dumps(local,ensure_ascii=False));generate()
            contract=json.loads(value("SELECT jsonb_build_object('owner',pg_get_userbyid(d.datdba),'super',r.rolsuper,'login',r.rolcanlogin,'create',has_schema_privilege('postgres','public','CREATE'),'usage',has_schema_privilege('postgres','public','USAGE'),'version',current_setting('server_version_num')::int) FROM pg_database d JOIN pg_roles r ON r.oid=d.datdba WHERE d.datname=current_database();"))
            check(contract['owner']=='supabase_admin' and contract['super'] and contract['login'] and not contract['create'] and contract['usage'] and 170000<=contract['version']<180000,'clone_bootstrap_contract_differs')
            print('明示した隔離コピー専用SQLでOFF導入とCOMMITを検証しています。本番SQLは実行しません。',flush=True)
            state['phase']='clone_install_commit';install=fixture_install((stage/'private-clone-install.sql.review-only').read_text());(stage/'private-clone-fixture-install.sql.review-only').write_text(install);query(install,role=contract['owner'])
            state['install_commit_verified']=True;state['phase']='clone_actual_after'
            actual=json.loads(query((stage/'private-clone-read-after.sql.read-only').read_text()).splitlines()[-1]);(stage/'private-clone-actual-after.json').write_text(json.dumps(actual,ensure_ascii=False));generate()
            print('隔離コピーの実afterから未使用undoを生成しました。COMMIT復旧と全データ一致を確認しています。',flush=True)
            state['phase']='clone_unused_undo_commit';query((stage/'private-clone-unused-undo.sql.review-only').read_text())
            state['phase']='full_restoration_comparison'
            check(value(CATALOG_SQL)==before_catalog and value(DEFAULT_ACL_SQL)==before_defaults,'catalog_or_acl_not_restored')
            check(json.loads(value(ROW_QUERIES_SQL))==rows and value(row_sql)==before_rows,'existing_rows_not_restored')
            check(json.loads(value(SEQUENCE_QUERIES_SQL))==seqs and value(seq_sql)==before_sequences,'existing_sequences_not_restored')
            check(not json.loads(run(['docker','inspect',source_name]))[0]['State']['Running'],'original_source_not_stopped')
            check(sha(stage/'private-fresh-before.json')==state['production_before_sha256'] and sha(stage/'private-prepared-install.sql.review-only')==status['artifacts']['private-prepared-install.sql.review-only']['sha256'],'original_evidence_changed')
            state.update(verified=True,phase='verified',unused_undo_commit_verified=True,full_catalog_data_sequences_restored=True,production_non_oid_contract_matched=True,financial_hash_matched=True);code=0
    except (Exception,KeyboardInterrupt) as error:
        if isinstance(error,RuntimeError) and error.args and re.fullmatch(r'[a-z_]{1,90}',str(error.args[0])):state['failure_code']=error.args[0]
    finally:
        if started:
            try:state['container_stopped']=subprocess.run(['docker','stop','-t','10',clone],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=30).returncode==0
            except (Exception,KeyboardInterrupt):state['container_stopped']=False
            if not state['container_stopped']:state['verified']=False;code=1
        if stage:(stage/'rehearsal-status.json').write_text(json.dumps(state,ensure_ascii=False,indent=2))
    result=('隔離cloneで本番との非OID契約・金融hash一致、明示OID対応の別SQLでOFF導入COMMIT→実after→未使用undoCOMMIT・全catalog/データ復元成功: '+stage.name+'。' if state['verified'] else '経費prepared隔離検証は未完了（段階: '+state.get('phase','準備')+'、理由: '+state.get('failure_code','private_log_review_required')+'）。')+'本番接続・本番prepared SQL実行・金額変換は行っていません。'
    print(result,flush=True)
    if sys.platform=='darwin':subprocess.run(['/usr/bin/pbcopy'],input=result,text=True,check=False)
    return code
if __name__=='__main__':sys.exit(main())
