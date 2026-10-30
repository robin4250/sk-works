"""Offline private review bundle generator. No database, network or deployment."""
import argparse
import hashlib
import json
from pathlib import Path
import re

SOURCE_SHA = '4277c2581a8fabb9e4dc0a9ee9ad07379d17afdd210006d49e74fa0b464e7fc6'


def read_capture(path):
    value = json.loads(Path(path).read_text())
    if isinstance(value, dict) and 'content' in value:
        raw = json.loads(value['content'][0]['text'])['result']
        fragment = raw[raw.index('['):raw.rindex(']') + 1]
        try:
            value = json.loads(fragment)
        except json.JSONDecodeError:
            value = json.loads(fragment.replace('\\"', '"').replace('\\\\', '\\'))
    if isinstance(value, list):
        assert len(value) == 1
        value = value[0]['metadata']
    return value


def literal(value):
    text = json.dumps(value, ensure_ascii=False, separators=(',', ':'))
    tag = '$reason_' + hashlib.sha256(text.encode()).hexdigest()[:16] + '$'
    assert tag not in text
    return tag + text + tag + '::jsonb'


def normalize_function(row):
    row = dict(row)
    row['attributes'] = dict(row['attributes'])
    match = re.search(r'\bAS (\$[A-Za-z_0-9]*\$)([\s\S]*?)\1', row['definition'])
    assert match, 'Unsupported function definition encoding'
    source = match[2]
    assert hashlib.md5(source.encode()).hexdigest() == row['source_md5'], 'Captured source digest differs'
    if 'prosrc' in row['attributes']:
        assert row['attributes']['prosrc'] == source, 'Captured source copies differ'
    row['attributes']['prosrc'] = source
    return row


def merge_captures(captures):
    result = {}
    for capture in captures:
        for key, rows in capture.items():
            if isinstance(rows, bool):
                assert rows is False, 'Additive module already exists'
                continue
            if not isinstance(rows, list):
                continue
            result.setdefault(key, [])
            for row in rows:
                if key == 'functions':
                    row = normalize_function(row)
                identity = json.dumps(row, sort_keys=True, ensure_ascii=False)
                if not any(json.dumps(old, sort_keys=True, ensure_ascii=False) == identity for old in result[key]):
                    result[key].append(row)
    functions = result['functions']
    assert len({row['attributes']['oid'] for row in functions}) == len(functions), 'Conflicting function captures'
    return result


def generate(source, metadata):
    assert hashlib.sha256(source.encode()).hexdigest() == SOURCE_SHA, 'Original candidate changed'
    matches = re.findall(r'CREATE FUNCTION ([a-z_]+\.[a-z_]+)\(([^)]*)\)\s*RETURNS ([a-z]+) LANGUAGE ([a-z]+) SECURITY (DEFINER|INVOKER) SET search_path=\'\' AS \$fn\$([\s\S]*?)\$fn\$;', source)
    assert len(matches) == 6, 'Expected exactly six additive functions'
    new_functions = []
    for name, args, returns, language, security, body in matches:
        signature = name + '(' + ','.join(arg.split()[-1] for arg in args.split(',') if arg.strip()) + ')'
        new_functions.append({'signature': signature, 'source_md5': hashlib.md5(body.encode()).hexdigest(),
                              'definer': security == 'DEFINER', 'language': language,
                              'authenticated': returns != 'trigger', 'return_oid': {'trigger': 2279, 'jsonb': 3802, 'integer': 23}[returns],
                              'argument_names': [arg.split()[0] for arg in args.split(',') if arg.strip()],
                              'argument_types': [{'uuid': 2950, 'date': 1082, 'bigint': 20, 'jsonb': 3802, 'boolean': 16, 'text': 25}[arg.split()[-1]] for arg in args.split(',') if arg.strip()]})
    before = literal(metadata)
    expected = literal(new_functions)
    relation_ids = ','.join(str(int(row['oid'])) for row in metadata['relations'])
    assert relation_ids
    comparisons = {
        'relations': f"select to_jsonb(c) item from pg_class c where c.oid in ({relation_ids})",
        'columns': f"select to_jsonb(a) item from pg_attribute a where a.attrelid in ({relation_ids}) and a.attnum>0 and not a.attisdropped",
        'constraints': f"select jsonb_build_object('attrs',to_jsonb(c),'definition',pg_get_constraintdef(c.oid)) item from pg_constraint c where c.conrelid in ({relation_ids})",
        'indexes': f"select jsonb_build_object('attrs',to_jsonb(i),'definition',pg_get_indexdef(i.indexrelid)) item from pg_index i where i.indrelid in ({relation_ids})",
        'triggers': f"select jsonb_build_object('attrs',to_jsonb(t),'definition',pg_get_triggerdef(t.oid)) item from pg_trigger t where t.tgrelid in ({relation_ids}) and not t.tgisinternal",
        'policies': f"select to_jsonb(policy_row) item from pg_policy policy_row where policy_row.polrelid in ({relation_ids})",
        'defaults': "select jsonb_build_object('attrs',to_jsonb(d),'schema',coalesce(n.nspname,'')) item from pg_default_acl d left join pg_namespace n on n.oid=d.defaclnamespace where d.defaclrole=(select oid from pg_roles where rolname='postgres') and (d.defaclnamespace=0 or n.nspname in ('public','payroll_tax_private'))",
    }
    # Captures store constraint attributes as `attrs` or `attributes`; normalize
    # this representation once while keeping every actual pg_catalog field.
    for key in ('constraints', 'indexes', 'triggers'):
        metadata[key] = [{('attrs' if k == 'attributes' else k): v for k, v in row.items()} for row in metadata.get(key, [])]
    before = literal(metadata)
    check_catalog = '''
 for e in select value from jsonb_array_elements((select payload from reason_review_before)->'functions') loop
  select * into p from pg_proc where oid=(e#>>'{attributes,oid}')::oid;
  if not found or to_jsonb(p) is distinct from e->'attributes' or pg_get_functiondef(p.oid) is distinct from e->>'definition' then
   raise exception 'Payroll reason dependency catalog changed; stop' using errcode='55000';
  end if;
 end loop;
'''
    for key, query in comparisons.items():
        check_catalog += f'''
 select coalesce(jsonb_agg(item order by item::text),'[]'::jsonb) into actual from ({query}) q;
 select coalesce(jsonb_agg(value order by value::text),'[]'::jsonb) into wanted from jsonb_array_elements((select payload from reason_review_before)->'{key}');
 if actual is distinct from wanted then raise exception 'Payroll reason {key} catalog changed; stop' using errcode='55000';end if;
'''
    sql = "-- PRIVATE REVIEW ONLY. Production HOLD. Installation exposes manual-adjustment capability; not authorized.\nBEGIN;\nSET LOCAL lock_timeout='3s';SET LOCAL statement_timeout='30s';\n"
    sql += f'create temporary table reason_review_before on commit drop as select {before} payload;\n'
    sql += f'create temporary table reason_review_expected on commit drop as select value payload from jsonb_array_elements({expected});\n'
    sql += 'do $reason_pre$ declare e jsonb;p pg_proc;actual jsonb;wanted jsonb;begin\n' + check_catalog
    sql += '''
 if not has_schema_privilege('authenticated','payroll_tax_private','USAGE') then raise exception 'Existing payroll schema usage missing';end if;
 if to_regclass('payroll_tax_private.adjustment_reasons') is not null then raise exception 'Reason table already exists; reconcile';end if;
 for e in select payload from reason_review_expected loop
  if to_regprocedure(e->>'signature') is not null then raise exception 'Reason function already exists; reconcile';end if;
 end loop;
end $reason_pre$;
'''
    lines = source.splitlines(keepends=True)
    wrappers = [i for i, line in enumerate(lines) if line.strip().upper() in ('BEGIN;', 'COMMIT;')]
    assert len(wrappers) == 2
    sql += ''.join(line for i, line in enumerate(lines) if i not in wrappers)
    sql += '\ndo $reason_post$ declare e jsonb;p pg_proc;actual jsonb;wanted jsonb;owner_id oid;auth_id oid;table_id oid;begin\n' + check_catalog
    sql += '''
 select oid into owner_id from pg_roles where rolname='postgres';select oid into auth_id from pg_roles where rolname='authenticated';
 for e in select payload from reason_review_expected loop
  select * into p from pg_proc where oid=to_regprocedure(e->>'signature');
  if not found or md5(p.prosrc) is distinct from e->>'source_md5' or p.proowner<>owner_id
   or p.prosecdef is distinct from (e->>'definer')::boolean or p.proconfig is distinct from ARRAY['search_path=""']::text[]
   or p.provolatile<>'v' or p.prokind<>'f' or p.proretset or p.proisstrict or p.proleakproof or p.proparallel<>'u'
   or p.prorettype<>(e->>'return_oid')::oid or p.procost<>100 or p.prorows<>0 or p.pronargdefaults<>0 or p.provariadic<>0
   or p.proargdefaults is not null or p.proallargtypes is not null or p.proargmodes is not null or p.probin is not null or p.prosqlbody is not null
   or coalesce(to_jsonb(p.proargnames),'[]'::jsonb) is distinct from e->'argument_names'
   or to_jsonb(p.proargtypes) is distinct from (select coalesce(jsonb_agg(value::text::oid),'[]'::jsonb) from jsonb_array_elements(e->'argument_types'))
   or (select lanname from pg_language where oid=p.prolang) is distinct from e->>'language'
   or exists(select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where a.grantor<>owner_id or a.privilege_type<>'EXECUTE' or a.is_grantable or a.grantee<>owner_id and (not (e->>'authenticated')::boolean or a.grantee<>auth_id))
   or ((e->>'authenticated')::boolean and not has_function_privilege('authenticated',p.oid,'EXECUTE')) then
   raise exception 'New payroll reason function contract/ACL differs; stop' using errcode='55000';
  end if;
 end loop;
 table_id:=to_regclass('payroll_tax_private.adjustment_reasons');
 if not exists(select 1 from pg_class c where c.oid=table_id and c.relowner=owner_id and c.relkind='r' and c.relrowsecurity and not c.relforcerowsecurity
  and not exists(select 1 from aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a where a.grantee<>owner_id))
  or exists(select 1 from pg_policy where polrelid=table_id)
  or not exists(select 1 from pg_trigger where tgrelid=table_id and tgname='adjustment_reason_history_immutable'
    and tgfoid='payroll_tax_private.guard_adjustment_reason_history()'::regprocedure and tgenabled='O' and tgtype=27) then
  raise exception 'New payroll reason table security/append-only trigger differs; stop' using errcode='55000';
 end if;
end $reason_post$;
-- Private function and table receipt only; no employee/payroll business-row read.
select n.nspname schema,p.proname name,pg_get_functiondef(p.oid) definition,md5(p.prosrc) source_md5,to_jsonb(p) attributes
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where exists(select 1 from reason_review_expected e where to_regprocedure(e.payload->>'signature')=p.oid)
 or exists(select 1 from jsonb_array_elements((select payload from reason_review_before)->'functions') e where (e#>>'{attributes,oid}')::oid=p.oid)
order by n.nspname,p.proname;
COMMIT;
'''
    return sql, new_functions


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--catalog', action='append', required=True)
    parser.add_argument('--source', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    metadata = merge_captures([read_capture(path) for path in args.catalog])
    sql, expected = generate(Path(args.source).read_text(), metadata)
    output = Path(args.output); output.mkdir(parents=True, exist_ok=True)
    (output / 'guarded-forward.sql.review-only').write_text(sql)
    plan = {'status': 'REVIEW ONLY; production HOLD; not applied', 'source_sha256': SOURCE_SHA,
            'guarded_forward_sha256': hashlib.sha256(sql.encode()).hexdigest(),
            'existing_functions_unchanged': len(metadata['functions']), 'existing_tables_unchanged': len(metadata['relations']),
            'new_functions': [item['signature'] for item in expected],
            'activation': 'Installing capability version 1 immediately enables permitted existing-client manual adjustments; no separate master OFF switch',
            'installation_business_dml': False,
            'later_usage': 'Existing saver may recalculate applicable automatic draft payroll; finalized values remain protected by existing saver',
            'history_ui': 'Read RPC exists in candidate but client history display is not connected',
            'pause_receipt': 'Use actual returned function rows including definition/source_md5/full attributes; capture reason-table class/constraints/triggers/policies immediately after COMMIT in an independent read before user writes',
            'recovery': 'No destructive uninstall or source rollback. Preserve append-only reason records. A separately reviewed disable of new entry EXECUTE may pause new operations after writer quiescence, preserving all originals and legacy APIs.'}
    (output / 'review-plan.json').write_text(json.dumps(plan, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({key: plan[key] for key in ('status', 'guarded_forward_sha256', 'existing_functions_unchanged', 'existing_tables_unchanged')}))


if __name__ == '__main__':
    main()
