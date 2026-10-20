#!/usr/bin/env python3
"""Install existing common-payroll dependencies in an offline clone, then rollback.

No adoption, activation, publication, worker conditions or payroll refresh runs.
The original successful restore and its archive are never started or modified.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import uuid

import owner_expense_off_rehearsal as transport

EXPECTED = {
 'supabase/migrations/20261009201229_company_allowance_identity_lifecycle.sql':'edacd1d8aac3ac0dd7219954192871725782369c82824173b2c73afe8aad3c3d',
 'tool/staged_company_common_allowances.sql.review-only':'8f4c3b1b1cd07519174c88441c5e4b7eea325bbdd99b6ae455897b04e9786e46',
 'docs/candidates/company_common_payroll_bridge_20261020.sql.review-only':'043fa73f7f997c67df21e4544073febe6f351d82f1fcd1b2771c953dd92e1d45',
 'docs/candidates/company_common_payroll_effective_20261020.sql.review-only':'3a6aa28e29de9aee6cbd2464df2cc4361806ccad0aa55f901ec89e1f399eb023',
}
SCOPES = "n.nspname IN ('public','private','auth') OR n.nspname LIKE 'payroll\\_%' ESCAPE '\\' OR n.nspname LIKE '%\\_private' ESCAPE '\\'"
CATALOG_SQL = """SELECT md5(jsonb_build_object(
 'schemas',(SELECT coalesce(jsonb_agg(jsonb_build_array(n.oid,n.nspname,n.nspowner,n.nspacl) ORDER BY n.oid),'[]') FROM pg_namespace n WHERE SCOPE),
 'relations',(SELECT coalesce(jsonb_agg(jsonb_build_array(c.oid,c.relname,c.relkind,c.relowner,c.relacl,c.relrowsecurity,c.relforcerowsecurity,c.reloptions) ORDER BY c.oid),'[]') FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE SCOPE),
 'attributes',(SELECT coalesce(jsonb_agg(to_jsonb(a) ORDER BY a.attrelid,a.attnum),'[]') FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE SCOPE),
 'functions',(SELECT coalesce(jsonb_agg(jsonb_build_array(p.oid,pg_get_functiondef(p.oid),p.proowner,p.proacl,p.proconfig,p.prosecdef) ORDER BY p.oid),'[]') FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE (SCOPE) AND p.prokind IN ('f','p')),
 'policies',(SELECT coalesce(jsonb_agg(to_jsonb(p) ORDER BY p.oid),'[]') FROM pg_policy p JOIN pg_class c ON c.oid=p.polrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE SCOPE),
 'triggers',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.oid),'[]') FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE SCOPE)
)::text);""".replace('SCOPE',SCOPES)
BUSINESS_SQL = """CREATE TEMP TABLE common_data_fingerprints(name text PRIMARY KEY,hash text);
DO $hash$ DECLARE r record; h text; BEGIN
 FOR r IN SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE (SCOPE) AND n.nspname NOT IN ('company_allowance_identity_private','company_common_allowance_private') AND c.relkind='r' ORDER BY n.nspname,c.relname LOOP
 EXECUTE format('SELECT md5(coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text),''[]'')::text) FROM %I.%I x',r.nspname,r.relname) INTO h;
 INSERT INTO common_data_fingerprints VALUES(r.nspname||'.'||r.relname,h);
 END LOOP;
END $hash$;
SELECT md5(coalesce(jsonb_agg(jsonb_build_array(name,hash) ORDER BY name),'[]')::text) FROM common_data_fingerprints;""".replace('SCOPE',SCOPES)
PREFLIGHT = """DO $guard$ BEGIN
 IF to_regnamespace('company_allowance_identity_private') IS NOT NULL OR to_regnamespace('company_common_allowance_private') IS NOT NULL
 THEN RAISE EXCEPTION 'new common schemas already exist'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('payroll_unit_private.augment_settings(uuid,uuid,date,date,jsonb)')) IS DISTINCT FROM '5c51172a6169beb90a7ddbb6ae443cd6'
 OR (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('payroll_unit_private.read_conditions(uuid,uuid,date)')) IS DISTINCT FROM 'cf298ba4b1e848ab89a67623f7466bcd'
 THEN RAISE EXCEPTION 'existing unit prerequisite differs; never reinstall older unit migration'; END IF;
END $guard$;"""
POSTFLIGHT = """DO $verify$ DECLARE r record; tables integer:=0; BEGIN
 IF to_regprocedure('public.read_company_common_allowances_admin(uuid)') IS NULL
 OR to_regprocedure('public.save_company_common_allowances(uuid,text,bigint,jsonb,uuid,jsonb,jsonb,boolean)') IS NULL
 OR to_regprocedure('public.read_company_common_payroll_publications(uuid)') IS NULL
 OR to_regprocedure('public.publish_company_common_payroll(uuid,text,date,bigint,jsonb,bigint,uuid)') IS NULL
 THEN RAISE EXCEPTION 'common public contract incomplete'; END IF;
 FOR r IN SELECT c.oid,c.relrowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname IN ('company_allowance_identity_private','company_common_allowance_private') AND c.relkind='r' LOOP
 tables:=tables+1;
 IF NOT r.relrowsecurity OR has_table_privilege('authenticated',r.oid,'SELECT,INSERT,UPDATE,DELETE') OR has_table_privilege('anon',r.oid,'SELECT,INSERT,UPDATE,DELETE')
 THEN RAISE EXCEPTION 'common storage exposed or RLS disabled'; END IF;
 END LOOP;
 IF tables<>11 OR EXISTS(SELECT 1 FROM company_common_allowance_private.payroll_activation)
 OR EXISTS(SELECT 1 FROM company_common_allowance_private.payroll_publications)
 THEN RAISE EXCEPTION 'unexpected common objects or nonempty activation/publication'; END IF;
END $verify$;"""

def build_install(bundle):
    if bundle.get('source_main')!='c8216d9a31e0d8340c9ec123307907bc148191a8' or set(bundle.get('files',{}))!=set(EXPECTED):
        raise RuntimeError('reviewed_source_set_mismatch')
    parts=[PREFLIGHT]
    for path,digest in EXPECTED.items():
        sql=bundle['files'][path]
        if hashlib.sha256(sql.encode()).hexdigest()!=digest: raise RuntimeError('reviewed_source_hash_mismatch')
        if path.endswith('.review-only'):
            sql,count=re.subn(r'^begin;\s*$','',sql,count=1,flags=re.I|re.M)
            if count!=1 or not re.search(r'commit;\s*$',sql,re.I): raise RuntimeError('outer_transaction_shape_mismatch')
            sql=re.sub(r'commit;\s*$','',sql,flags=re.I)
        if re.search(r'^\s*(BEGIN|COMMIT|ROLLBACK|START TRANSACTION)\s*;',sql,re.I|re.M): raise RuntimeError('inner_transaction_refused')
        parts.append(sql)
    return 'BEGIN;\n'+ '\n'.join(parts)+'\n'+POSTFLIGHT+'\nROLLBACK;'

def main():
    os.umask(0o077)
    stage=None; clone=None; started=False
    status={'schema':1,'verified':False,'production_connected':False,'activation_written':False,'payroll_recalculated':False,'real_jwt_verified':False}
    try:
        if sys.platform!='darwin': raise RuntimeError('mac_required')
        if os.environ.get('DOCKER_HOST') or os.environ.get('DOCKER_CONTEXT'): raise RuntimeError('docker_override_refused')
        bundle=json.loads((Path(__file__).parent/'common_payroll_sources.json').read_text())
        install=build_install(bundle)
        root=Path.home()/'SKO-source-backups'; source=root/transport.SOURCE
        if any(p.is_symlink() for p in (source,*source.parents)) or root.stat().st_mode&0o077: raise RuntimeError('private_source_required')
        original=json.loads((source/'rehearsal-status.json').read_text())
        if not original.get('archive_restore_verified') or not original.get('container_stopped'): raise RuntimeError('verified_stopped_source_required')
        name=original['container']
        if not re.fullmatch(r'sko-restore-[a-f0-9]{12}',name): raise RuntimeError('source_name_invalid')
        stage=Path(tempfile.mkdtemp(prefix='payroll-common-rehearsal-',dir=root))
        env={k:v for k,v in os.environ.items() if not k.startswith('PG')}
        with (stage/'private-errors.log').open('xb') as errors:
            def run(args,data=None,timeout=120):
                return subprocess.run(args,env=env,input=data,stdin=subprocess.DEVNULL if data is None else None,
                    stdout=subprocess.PIPE,stderr=errors,check=True,timeout=timeout).stdout
            context=json.loads(run(['docker','context','inspect']))
            if not context[0]['Endpoints']['docker']['Host'].startswith('unix://'): raise RuntimeError('remote_docker_refused')
            src=json.loads(run(['docker','inspect',name]))[0]
            if src['State']['Running'] or src['HostConfig']['NetworkMode']!='none' or src['Config']['Image']!=transport.BASE_IMAGE or src['Config']['Labels'].get('sko-purpose')!='offline-restore': raise RuntimeError('source_container_mismatch')
            status['phase']='clone'
            print('元の復元DBを保持し、通信なしの別DBで既存共通手当の依存4原本を確認します。',flush=True)
            image=run(['docker','commit',name],timeout=300).decode().strip()
            if not re.fullmatch(r'sha256:[a-f0-9]{64}',image): raise RuntimeError('clone_image_invalid')
            status['private_local_image']=image; clone='sko-common-'+uuid.uuid4().hex[:12]; status['container']=clone
            run(transport.clone_command(clone,image)); started=True
            for attempt in range(60):
                result=subprocess.run(['docker','exec',clone,'pg_isready','-h','/tmp','-U','postgres'],env=env,stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=errors,timeout=5)
                if result.returncode==0: break
                time.sleep(1)
            else: raise RuntimeError('clone_not_ready')
            info=json.loads(run(['docker','inspect',clone]))[0]
            if info['HostConfig']['NetworkMode']!='none' or info['HostConfig'].get('PortBindings'): raise RuntimeError('clone_not_isolated')
            def query(sql,role='postgres'):
                return run(['docker','exec','-i',clone,'psql','-X','-w','-h','/tmp','-U',role,'-d','postgres','-q','-A','-t','-v','ON_ERROR_STOP=1'],("SET statement_timeout='60s'; SET lock_timeout='3s';\n"+sql).encode()).decode().strip()
            def value(sql): return query(sql).splitlines()[-1]
            if value('SHOW cron.launch_active_jobs;')!='off': raise RuntimeError('cron_not_disabled')
            status['phase']='database_properties'; query(transport.DATABASE_BASELINE_SQL,role='supabase_admin')
            before=value(CATALOG_SQL); business=value(BUSINESS_SQL)
            status['phase']='dependency_install_rollback'; (stage/'reviewed-install-rollback.sql').write_text(install)
            query(install)
            if value(CATALOG_SQL)!=before: raise RuntimeError('catalog_not_restored')
            if value(BUSINESS_SQL)!=business: raise RuntimeError('existing_business_changed')
            status.update(verified=True,phase='verified',catalog_restored=True,business_unchanged=True)
        result=f'隔離実DBで社内共通手当の依存4原本導入・RLS/非公開表・未有効確認・全rollback成功: {stage.name}。手当保存/給与再計算/実JWT/本番適用は未実施。'; code=0
    except (Exception,KeyboardInterrupt):
        result='社内共通手当の隔離導入検証は未完了（段階: '+status.get('phase','準備')+'）。元の復元DB・バックアップ・本番は変更していません。'; code=1
    finally:
        if started:
            try: status['container_stopped']=subprocess.run(['docker','stop','-t','10',clone],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=30).returncode==0
            except (Exception,KeyboardInterrupt): status['container_stopped']=False
        if started and not status.get('container_stopped'):
            status.update(verified=False,phase='clone_stop')
            result='社内共通手当の隔離DB停止を確認できません。元の復元DB・バックアップ・本番は変更していません。'; code=1
        if stage: (stage/'common-rehearsal-status.json').write_text(json.dumps(status,ensure_ascii=False,indent=2))
    print(result,flush=True)
    if sys.platform=='darwin': subprocess.run(['/usr/bin/pbcopy'],input=result,text=True,check=False)
    return code

if __name__=='__main__': sys.exit(main())
