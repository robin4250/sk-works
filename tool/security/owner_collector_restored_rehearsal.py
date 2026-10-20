#!/usr/bin/env python3
"""Offline collector storage rehearsal on a clone of the verified restored DB."""
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
# Reuse the already verified restore-source/isolation/database-property pattern.
import owner_expense_off_rehearsal as base

CANDIDATE_SHA256='b96f6e4365e2e992886f38dad0f777e55665f18b03525cddf4edbdf746348207'
CATALOG_SQL="""select jsonb_build_object(
 'roles',(select jsonb_agg(jsonb_build_array(rolname,rolsuper,rolinherit,rolcreaterole,rolcreatedb,rolcanlogin,rolreplication,rolbypassrls,rolvaliduntil) order by rolname) from pg_roles),
 'members',(select jsonb_agg(to_jsonb(m) order by roleid,member,grantor) from pg_auth_members m),
 'schemas',(select jsonb_agg(jsonb_build_array(oid,nspname,nspowner,nspacl) order by oid) from pg_namespace where nspname !~ '^pg_'),
 'relations',(select jsonb_agg(jsonb_build_array(c.oid,n.nspname,c.relname,c.relkind,c.relowner,c.relacl,c.relrowsecurity,c.relforcerowsecurity) order by c.oid) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname !~ '^pg_' and n.nspname<>'information_schema'),
 'functions',(select jsonb_agg(jsonb_build_array(p.oid,pg_get_functiondef(p.oid),p.proowner,p.proacl,p.proconfig,p.prosecdef) order by p.oid) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname !~ '^pg_' and n.nspname<>'information_schema' and p.prokind in ('f','p')),
 'policies',(select jsonb_agg(to_jsonb(p) order by p.oid) from pg_policy p),
 'triggers',(select jsonb_agg(to_jsonb(t) order by t.oid) from pg_trigger t where not t.tgisinternal),
 'event_triggers',(select jsonb_agg(to_jsonb(t) order by t.oid) from pg_event_trigger t)
)::text;"""
ROW_QUERIES_SQL="""select coalesce(jsonb_agg(format('select %L as relation,md5(coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),%L::jsonb)::text) as digest from %I.%I x',n.nspname||'.'||c.relname,'[]',n.nspname,c.relname) order by n.nspname,c.relname),'[]'::jsonb)
from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.relkind in ('r','p') and n.nspname in ('public','private','auth','storage','vault','cron');"""


SEQUENCE_QUERIES_SQL="""select coalesce(jsonb_agg(format('select %L as relation,last_value,is_called from %I.%I',n.nspname||'.'||c.relname,n.nspname,c.relname) order by n.nspname,c.relname),'[]'::jsonb)
from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.relkind='S' and n.nspname in ('public','private','auth','storage','vault','cron');"""


def clone_command(name,image):
    args=base.clone_command(name,image)
    args[args.index('sko-purpose=expense-off-rehearsal')]='sko-purpose=collector-restored-rehearsal'
    return args


def transaction_sql(bundle):
    candidate=bundle['candidate']
    if hashlib.sha256(candidate.encode()).hexdigest()!=CANDIDATE_SHA256:
        raise RuntimeError('reviewed_collector_candidate_mismatch')
    if len(re.findall(r'^begin;\s*$',candidate,re.I|re.M))!=1 or not candidate.endswith('commit;\n'):
        raise RuntimeError('candidate_transaction_boundary_changed')
    candidate=re.sub(r'^begin;\s*$','',candidate,count=1,flags=re.I|re.M).removesuffix('commit;\n')
    scenario=bundle['scenario']
    if re.search(r'^\s*(COMMIT|ROLLBACK|START TRANSACTION|BEGIN)\s*;',candidate+'\n'+scenario,re.I|re.M):
        raise RuntimeError('unexpected_transaction_control')
    return "BEGIN;\nCREATE ROLE sko_security_collector_ingest NOLOGIN NOINHERIT NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOREPLICATION;\n"+candidate+'\n'+scenario+'\nROLLBACK;'


def main():
    os.umask(0o077)
    stage=None; clone=None; started=False
    status={'schema':1,'verified':False,'production_connected':False,'real_signature_verified':False,
            'real_master_proof_verified':False,'transport_implemented':False}
    result='collector隔離検証は未完了です。'
    try:
        if sys.platform!='darwin': raise RuntimeError('mac_required')
        if os.environ.get('DOCKER_HOST') or os.environ.get('DOCKER_CONTEXT'): raise RuntimeError('docker_override_refused')
        root=Path.home()/'SKO-source-backups'; source=root/base.SOURCE
        if any(p.is_symlink() for p in (source,*source.parents)) or root.stat().st_mode&0o077:
            raise RuntimeError('private_source_required')
        original=json.loads((source/'rehearsal-status.json').read_text())
        if not original.get('archive_restore_verified') or not original.get('container_stopped'):
            raise RuntimeError('verified_stopped_source_required')
        name=original['container']
        if not re.fullmatch(r'sko-restore-[a-f0-9]{12}',name): raise RuntimeError('source_name_invalid')
        bundle=json.loads((Path(__file__).parent/'collector_restored_bundle.json').read_text())
        sql=transaction_sql(bundle)
        stage=Path(tempfile.mkdtemp(prefix='collector-restored-rehearsal-',dir=root))
        env={k:v for k,v in os.environ.items() if not k.startswith('PG')}
        with (stage/'private-errors.log').open('xb') as errors:
            def run(args,data=None,timeout=120):
                return subprocess.run(args,env=env,input=data,stdin=subprocess.DEVNULL if data is None else None,
                    stdout=subprocess.PIPE,stderr=errors,check=True,timeout=timeout).stdout
            context=json.loads(run(['docker','context','inspect']))
            if not context[0]['Endpoints']['docker']['Host'].startswith('unix://'): raise RuntimeError('remote_docker_refused')
            src=json.loads(run(['docker','inspect',name]))[0]
            if src['State']['Running'] or src['HostConfig']['NetworkMode']!='none' or src['HostConfig'].get('PortBindings') or src['Config']['Image']!=base.BASE_IMAGE:
                raise RuntimeError('source_container_mismatch')
            if src['Config']['Labels'].get('sko-purpose')!='offline-restore': raise RuntimeError('source_label_mismatch')
            print('復元成功済みDBから通信なしの別クローンを作成します。元DB・バックアップは保持します。',flush=True)
            status['phase']='clone'
            image=run(['docker','commit',name],timeout=300).decode().strip()
            if not re.fullmatch(r'sha256:[a-f0-9]{64}',image): raise RuntimeError('clone_image_invalid')
            status['private_local_image']=image
            clone='sko-collector-'+uuid.uuid4().hex[:12]; status['container']=clone
            run(clone_command(clone,image)); started=True
            for attempt in range(60):
                ready=subprocess.run(['docker','exec',clone,'pg_isready','-h','/tmp','-U','postgres'],env=env,
                    stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=errors,timeout=5)
                if ready.returncode==0: break
                time.sleep(1)
            else: raise RuntimeError('clone_not_ready')
            info=json.loads(run(['docker','inspect',clone]))[0]
            if info['HostConfig']['NetworkMode']!='none' or info['HostConfig'].get('PortBindings'):
                raise RuntimeError('clone_not_isolated')
            def query(text,role='postgres'):
                return run(['docker','exec','-i',clone,'psql','-X','-w','-h','/tmp','-U',role,'-d','postgres',
                    '-q','-A','-t','-v','ON_ERROR_STOP=1'],("SET statement_timeout='30s';SET lock_timeout='3s';\n"+text).encode()).decode().strip()
            def value(text): return query(text).splitlines()[-1]
            if value('SHOW cron.launch_active_jobs;')!='off': raise RuntimeError('cron_not_disabled')
            query(base.DATABASE_BASELINE_SQL,role='supabase_admin')
            status['database_owner_acl_matched']=True; status['phase']='baseline'
            preflight="""select to_regrole('sko_security_collector_ingest') is null
             and to_regclass('private.security_collector_control') is null
             and to_regclass('private.security_collector_events') is null
             and to_regclass('private.security_collector_read_audit') is null
             and to_regprocedure('private.consume_reauthentication_proof(text,jsonb,text)') is not null
             and to_regprocedure('private.account_access_allowed()') is not null
             and to_regprocedure('public.is_current_user_master_admin()') is not null;"""
            if value("SELECT to_regprocedure('private.consume_reauthentication_proof(text,jsonb,text)') is not null;")!='t':
                status['required_dependency']='existing_reauthentication_consumer'
                raise RuntimeError('reauth_consumer_missing')
            if value(preflight)!='t': raise RuntimeError('collector_or_reauth_baseline_differs')
            before_catalog=value(CATALOG_SQL)
            row_queries=json.loads(value(ROW_QUERIES_SQL))
            if not row_queries: raise RuntimeError('restored_business_tables_required')
            row_sql="SELECT jsonb_agg(to_jsonb(t) order by relation)::text FROM ("+' UNION ALL '.join(row_queries)+") t;"
            before_rows=value(row_sql)
            sequence_queries=json.loads(value(SEQUENCE_QUERIES_SQL))
            sequence_sql="SELECT coalesce(jsonb_agg(to_jsonb(s) order by relation),'[]'::jsonb)::text FROM ("+' UNION ALL '.join(sequence_queries)+") s;" if sequence_queries else "SELECT '[]';"
            before_sequences=value(sequence_sql)
            (stage/'before-catalog-private.json').write_text(before_catalog)
            (stage/'before-table-digests-private.json').write_text(before_rows)
            (stage/'before-sequences-private.json').write_text(before_sequences)
            (stage/'rehearsal.sql').write_text(sql)
            print('collector原本SQLの導入・既定OFF・権限拒否・合成イベント再実行を検証し、全変更を取り消します。',flush=True)
            status['phase']='collector_transaction'; query(sql)
            status['phase']='rollback_verification'
            if value(CATALOG_SQL)!=before_catalog: raise RuntimeError('catalog_not_restored')
            if json.loads(value(ROW_QUERIES_SQL))!=row_queries: raise RuntimeError('table_set_changed')
            if value(row_sql)!=before_rows: raise RuntimeError('existing_table_rows_changed')
            if json.loads(value(SEQUENCE_QUERIES_SQL))!=sequence_queries or value(sequence_sql)!=before_sequences:
                raise RuntimeError('existing_sequences_changed')
            if value(preflight)!='t': raise RuntimeError('collector_objects_not_rolled_back')
            status.update(verified=True,phase='verified',rollback_verified=True,existing_tables_unchanged=True,
                existing_sequences_unchanged=True,default_off_verified=True,api_role_denial_verified=True,bridge_isolation_verified=True,
                event_idempotence_verified=True,metadata_allowlist_verified=True,restored_table_count=len(row_queries))
        result=f'隔離実DBでcollector原本SQL・既定OFF・API権限拒否・合成イベント再実行・既存表不変・全rollback成功: {stage.name}。本番適用・実署名輸送・Master実認証・ハニー/動的の実運用は未実施。'
        code=0
    except (Exception,KeyboardInterrupt):
        result='collector隔離検証は未完了（段階: '+status.get('phase','準備')+'）。元の復元DB・バックアップ・本番は変更していません。'
        if status.get('required_dependency'):
            result='collector検証を停止: 既存の再認証証明consumerが必要です。代替の偽認証は追加していません。元DB・バックアップ・本番は変更していません。'
        code=1
    finally:
        if started:
            try:
                stopped=subprocess.run(['docker','stop','-t','10',clone],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=30)
                status['container_stopped']=stopped.returncode==0
            except (Exception,KeyboardInterrupt): status['container_stopped']=False
        if started and not status.get('container_stopped'):
            status['verified']=False; code=1
            result='collector検証の専用クローン停止を確認できません。元DB・バックアップ・本番は変更していません。'
        if stage: (stage/'collector-rehearsal-status.json').write_text(json.dumps(status,ensure_ascii=False,indent=2))
    print(result,flush=True)
    if sys.platform=='darwin': subprocess.run(['/usr/bin/pbcopy'],input=result,text=True,check=False)
    return code


if __name__=='__main__': sys.exit(main())
