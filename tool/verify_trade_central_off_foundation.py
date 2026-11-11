#!/usr/bin/env python3
"""Isolated PostgreSQL17 only. Never accepts a hosted URL."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
URL = os.environ.get('TRADE_GATE_FIXTURE_DATABASE_URL', '')
if not URL.startswith('postgresql://postgres:fixture-only@127.0.0.1:'):
    raise SystemExit('explicit loopback fixture URL required')

def sql(source, *, ok=True):
    run = subprocess.run(['psql', URL, '-X', '-At', '-v', 'ON_ERROR_STOP=1'], input=source,
                         text=True, capture_output=True, timeout=30)
    if (run.returncode == 0) != ok:
        raise AssertionError(run.stderr[-2000:] or run.stdout[-2000:])
    return run.stdout.strip()

baseline = json.loads((ROOT/'tool/fixtures/trade_central_off/observed_baseline.json').read_text())
candidate = (ROOT/'docs/candidates/trade_central_off_foundation_20261024.sql.review-only').read_text()
sql('''create role anon; create role authenticated; create role service_role;
create schema auth; create schema private;
create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('fixture.actor',true),'')::uuid$$;
create function public.is_current_user_master_admin() returns boolean language sql stable as $$select current_setting('fixture.master',true)='true'$$;
create table private.master_feature_settings(feature_key text primary key,
 enabled boolean not null default true,updated_at timestamptz not null default now(),
 updated_by uuid references auth.users(id));
revoke all on private.master_feature_settings from public;
grant all on private.master_feature_settings to postgres;
alter table private.master_feature_settings enable row level security;
'''+f"alter table private.master_feature_settings add constraint master_feature_settings_feature_key_check {baseline['constraint']};")
for index, name in enumerate(['vehicle_management','route_assignment','traffic_nearest_station','traffic_train_transfer','traffic_bus_stop']):
    sql(f"insert into private.master_feature_settings(feature_key,enabled) values('{name}',{'true' if index%2 else 'false'});")
for routine in baseline['routines'].values():
    sql(routine['definition'])
sql('''revoke all on function public.current_master_feature_flags() from public,anon;
revoke all on function public.set_master_feature_enabled(text,boolean) from public,anon;
grant execute on function public.current_master_feature_flags() to authenticated,service_role;
grant execute on function public.set_master_feature_enabled(text,boolean) to authenticated,service_role;
revoke all on function private.require_master_optional_feature(text) from public,anon,authenticated,service_role;''')

digest_query = """select md5(coalesce((select jsonb_agg(to_jsonb(t) order by feature_key)::text from private.master_feature_settings t),'null')||coalesce((select jsonb_agg(jsonb_build_object('oid',oid,'source',prosrc,'acl',proacl,'owner',proowner,'config',proconfig,'definer',prosecdef,'volatility',provolatile) order by oid)::text from pg_proc where pronamespace in ('public'::regnamespace,'private'::regnamespace)),'null'));"""
before = sql(digest_query)
sql("alter function public.set_master_feature_enabled(text,boolean) rename to temporarily_wrong_setter;")
sql(candidate, ok=False)
sql("alter function public.temporarily_wrong_setter(text,boolean) rename to set_master_feature_enabled;")
assert before == sql(digest_query), 'failed install changed original catalog/rows'
sql(candidate)
assert sql("select enabled from private.master_feature_settings where feature_key='trade_document_reciprocal_seals'") == 'f'
sql('select private.require_trade_document_reciprocal_seals()', ok=False)
sql(candidate, ok=False)  # Never make a repeated install reset an enabled flag.
assert sql("select enabled from private.master_feature_settings where feature_key='trade_document_reciprocal_seals'") == 'f'
actor = "set fixture.actor='00000000-0000-0000-0000-000000000001'; set fixture.master='true';"
sql(actor+" select public.set_master_feature_enabled('trade_document_reciprocal_seals',true)", ok=False)
for role in ['anon','authenticated','service_role']:
    assert sql(f"select has_function_privilege('{role}','private.require_trade_document_reciprocal_seals()','execute')") == 'f'
assert sql("select public.current_master_feature_flags() is null") == 't'
assert sql(actor+"select public.current_master_feature_flags()->>'trade_document_reciprocal_seals'").endswith('false')
sql("delete from private.master_feature_settings where feature_key='trade_document_reciprocal_seals'")
sql('select private.require_trade_document_reciprocal_seals()', ok=False)
assert sql(actor+"select public.current_master_feature_flags()->>'trade_document_reciprocal_seals'").endswith('false')
sql("alter table private.master_feature_settings alter column enabled drop not null; insert into private.master_feature_settings(feature_key,enabled) values('trade_document_reciprocal_seals',null)")
sql('select private.require_trade_document_reciprocal_seals()', ok=False)
assert sql(actor+"select public.current_master_feature_flags()->>'trade_document_reciprocal_seals'").endswith('false')
sql("update private.master_feature_settings set enabled=true where feature_key='trade_document_reciprocal_seals'; alter table private.master_feature_settings alter column enabled set not null;")
sql('select private.require_trade_document_reciprocal_seals()')
holder = subprocess.Popen(['psql',URL,'-X','-At','-v','ON_ERROR_STOP=1'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
holder.stdin.write("begin; select private.require_trade_document_reciprocal_seals(); select 'guard-lock-held'; select pg_sleep(2); commit;\n")
holder.stdin.close()
deadline=time.monotonic()+10
while True:
    line=holder.stdout.readline()
    if 'guard-lock-held' in line: break
    if not line or time.monotonic()>deadline: raise AssertionError('holder did not acquire gate lock')
sql("set statement_timeout='200ms'; update private.master_feature_settings set enabled=false where feature_key='trade_document_reciprocal_seals'",ok=False)
assert holder.wait(timeout=10)==0, holder.stderr.read()
sql("update private.master_feature_settings set enabled=false where feature_key='trade_document_reciprocal_seals'")
sql('select private.require_trade_document_reciprocal_seals()',ok=False)
assert sql("select md5(prosrc) from pg_proc where oid='private.require_master_optional_feature(text)'::regprocedure") == baseline['routines']['private.require_master_optional_feature(text)']['source_md5']
assert sql("select md5(prosrc) from pg_proc where oid='public.set_master_feature_enabled(text,boolean)'::regprocedure") == baseline['routines']['set_master_feature_enabled(text,boolean)']['source_md5']
assert sql("select to_regprocedure('public.set_master_feature_enabled_with_proof(text,boolean,text)') is null") == 't'
print(json.dumps({'pass':True,'native_postgres':True,'default_off':True,'missing_null_off_denied':True,'legacy_setter_rejects_new_key':True,'old_setter_and_guard_unchanged':True,'inflight_gate_lock_serializes_off':True,'proof_toggle_created':False,'business_functions_modified':False,'production_changed':False,'candidate_sha256':hashlib.sha256(candidate.encode()).hexdigest()}))
