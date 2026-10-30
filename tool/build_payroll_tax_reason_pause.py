"""Offline generator for a separately approved, non-destructive reason-entry pause."""
import argparse
import hashlib
import json
from pathlib import Path
from build_payroll_tax_reason_review import literal, normalize_function

ENTRIES = [
    'public.payroll_tax_adjustment_reason_contract_version()',
    'public.save_worker_payroll_tax_conditions_with_reason(uuid,uuid,date,bigint,jsonb,boolean,text)',
    'payroll_tax_private.save_conditions_with_reason(uuid,uuid,date,bigint,jsonb,boolean,text)',
]


def build(receipt):
    functions = [normalize_function(row) for row in receipt['functions']]
    assert functions and len({row['attributes']['oid'] for row in functions}) == len(functions)
    required = {('payroll_tax_private', 'guard_adjustment_reason_history'),
                ('payroll_tax_private', 'save_conditions_with_reason'),
                ('payroll_tax_private', 'read_adjustment_history'),
                ('public', 'save_worker_payroll_tax_conditions_with_reason'),
                ('public', 'read_worker_payroll_tax_adjustment_history'),
                ('public', 'payroll_tax_adjustment_reason_contract_version')}
    assert required <= {(row.get('schema'), row.get('name')) for row in functions}, 'Complete additive reason function receipt required'
    assert all(row.get('name') == row['attributes']['proname'] for row in functions), 'Function receipt names differ'
    assert receipt['reason_table']['class']['relname'] == 'adjustment_reasons'
    assert receipt['reason_table']['class']['relrowsecurity'] is True
    payload = literal({'functions': functions, 'reason_table': receipt['reason_table']})
    sql = "-- PRIVATE REVIEW ONLY. Separate permission-change approval and independently stopped writers required.\nBEGIN;\nSET LOCAL lock_timeout='3s';SET LOCAL statement_timeout='30s';\n"
    sql += f'create temporary table reason_pause_receipt on commit drop as select {payload} payload;\n'
    sql += '''do $pause_guard$ declare e jsonb;p pg_proc;actual jsonb;tid oid;signature text;begin
 if current_setting('sko.payroll_reason_writers_stopped',true) is distinct from 'verified-no-inflight' then
  raise exception 'Independently stopped reason writers required' using errcode='55000';end if;
 foreach signature in array ARRAY['public.payroll_tax_adjustment_reason_contract_version()',
  'public.save_worker_payroll_tax_conditions_with_reason(uuid,uuid,date,bigint,jsonb,boolean,text)',
  'payroll_tax_private.save_conditions_with_reason(uuid,uuid,date,bigint,jsonb,boolean,text)',
  'public.read_worker_payroll_tax_adjustment_history(uuid,uuid)',
  'payroll_tax_private.read_adjustment_history(uuid,uuid)',
  'payroll_tax_private.guard_adjustment_reason_history()'] loop
  if not exists(select 1 from jsonb_array_elements((select payload from reason_pause_receipt)->'functions') item
    where (item#>>'{attributes,oid}')::oid=to_regprocedure(signature)) then
   raise exception 'Reason pause target missing from committed receipt' using errcode='55000';end if;
 end loop;
 for e in select value from jsonb_array_elements((select payload from reason_pause_receipt)->'functions') loop
  select * into p from pg_proc where oid=(e#>>'{attributes,oid}')::oid;
  if not found or to_jsonb(p) is distinct from e->'attributes' or pg_get_functiondef(p.oid) is distinct from e->>'definition' then
   raise exception 'Reason pause committed function identity changed; stop' using errcode='55000';end if;
 end loop;
 tid:=to_regclass('payroll_tax_private.adjustment_reasons');
 select jsonb_build_object('class',to_jsonb(c),
  'constraints',(select coalesce(jsonb_agg(to_jsonb(k) order by k.oid),'[]'::jsonb) from pg_constraint k where k.conrelid=c.oid),
  'triggers',(select coalesce(jsonb_agg(to_jsonb(t) order by t.oid),'[]'::jsonb) from pg_trigger t where t.tgrelid=c.oid and not t.tgisinternal),
  'policies',(select coalesce(jsonb_agg(to_jsonb(policy_row) order by policy_row.oid),'[]'::jsonb) from pg_policy policy_row where policy_row.polrelid=c.oid))
 into actual from pg_class c where c.oid=tid;
 if actual is distinct from (select payload->'reason_table' from reason_pause_receipt) then
  raise exception 'Reason pause committed table security changed; stop' using errcode='55000';end if;
end $pause_guard$;
'''
    for signature in ENTRIES:
        sql += f'REVOKE EXECUTE ON FUNCTION {signature} FROM authenticated;\n'
    sql += '''do $pause_after$ declare e jsonb;p pg_proc;changed boolean;begin
 for e in select value from jsonb_array_elements((select payload from reason_pause_receipt)->'functions') loop
  select * into p from pg_proc where oid=(e#>>'{attributes,oid}')::oid;
  changed:=p.oid in ('public.payroll_tax_adjustment_reason_contract_version()'::regprocedure,
   'public.save_worker_payroll_tax_conditions_with_reason(uuid,uuid,date,bigint,jsonb,boolean,text)'::regprocedure,
   'payroll_tax_private.save_conditions_with_reason(uuid,uuid,date,bigint,jsonb,boolean,text)'::regprocedure);
  if not found or (to_jsonb(p)-'proacl') is distinct from ((e->'attributes')-'proacl')
   or (not changed and to_jsonb(p) is distinct from e->'attributes')
   or (changed and p.proacl::text is distinct from '{postgres=X/postgres}') then
   raise exception 'Reason pause changed an unexpected function contract';end if;
 end loop;
 if not has_function_privilege('authenticated','public.read_worker_payroll_tax_adjustment_history(uuid,uuid)','EXECUTE') then
  raise exception 'History read must remain available';end if;
end $pause_after$;
COMMIT;
'''
    return sql


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--receipt', required=True); parser.add_argument('--output', required=True)
    args = parser.parse_args()
    sql = build(json.loads(Path(args.receipt).read_text()))
    Path(args.output).write_text(sql)
    print(json.dumps({'status': 'REVIEW ONLY, not applied', 'sha256': hashlib.sha256(sql.encode()).hexdigest(),
                      'preserves': 'legacy API, all original functions, every reason/history/document row',
                      'effect': 'pause new capability and new reason writes; keep scoped reason-history reading'}))


if __name__ == '__main__':
    main()
