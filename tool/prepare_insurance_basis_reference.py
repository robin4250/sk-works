#!/usr/bin/env python3
"""Generate private, exact-observation-bound install/postflight/unused restore SQL.

No database connection. This does not deploy or mutate application data.
"""
import argparse
import hashlib
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[1]
CANDIDATE = ROOT / 'docs/candidates/insurance_basis_reference_20261024.sql.review-only'
INVENTORY = ROOT / 'tool/insurance_basis_reference_inventory.read-only.sql'


def source_body(definition):
    m = re.search(r'AS (\$\w*\$)([\s\S]*)\1\s*;?\s*$', definition)
    if not m:
        raise ValueError('function body delimiter differs')
    return m.group(2)


def sql_string(literal):
    escaped = literal.startswith('E')
    text = literal[2:-1] if escaped else literal[1:-1]
    text = text.replace("''", "'")
    if escaped:
        text = re.sub(r'\\(.)', lambda m: {'n': '\n', 'r': '\r', 't': '\t'}.get(m[1], m[1]), text)
    return text


def expected_after(before, candidate):
    after = json.loads(json.dumps(before))
    patch = candidate.split('do $patch$', 1)[1].split('end $patch$', 1)[0]
    literal = r"E?'(?:''|\\.|[^'])*'"
    events = re.compile(r"s:=pg_get_functiondef\('([^']+)'::regprocedure\);|old:=(" + literal + r");\s*new:=(" + literal + r");")
    current = None
    changed = {}
    for match in events.finditer(patch):
        if match[1]:
            current = match[1]
            changed[current] = before['routines'][current]['definition']
        else:
            old, new = sql_string(match[2]), sql_string(match[3])
            if not current or old not in changed[current]:
                raise ValueError('unmatched exact-source patch anchor')
            changed[current] = changed[current].replace(old, new)
    if len(changed) != 4:
        raise ValueError('expected exactly four existing routine patches')
    for identity, definition in changed.items():
        old_body = source_body(before['routines'][identity]['definition'])
        if hashlib.md5(old_body.encode()).hexdigest() != before['routines'][identity]['source_md5']:
            raise ValueError('original source definition/hash mismatch')
        after['routines'][identity]['source_md5'] = hashlib.md5(source_body(definition).encode()).hexdigest()
        after['routines'][identity]['definition'] = definition
    # New routine bodies are literal candidate source, not generated from an actual-after observation.
    added = re.findall(r'create function ([\w.]+)\(([^)]*)\) returns (\w+)\s+([\s\S]*?)as \$fn\$([\s\S]*?)\$fn\$;', candidate)
    if len(added) != 6:
        raise ValueError('expected exactly six new routines')
    for name, args, returns, attrs, body in added:
        identity = name + '(' + ','.join(arg.strip().split()[-1] for arg in args.split(',')) + ')'
        if identity not in before['routines'] or before['routines'][identity]['present']:
            raise ValueError('new routine is not an observed absent prerequisite')
        callable_by_member = name in (
            'payroll_tax_private.insurance_income_history',
            'public.read_worker_payroll_insurance_income_history',
            'public.read_worker_payroll_tax_conditions_with_insurance_reference')
        after['routines'][identity] = dict(is_new=True, present=True,
            source_md5=hashlib.md5(body.encode()).hexdigest(), definition=None, owner='postgres',
            acl=['postgres=X/postgres'] + (['authenticated=X/postgres'] if callable_by_member else []),
            config=['search_path=""'], definer='security definer' in attrs,
            volatility='i' if 'immutable' in attrs else 's' if 'stable' in attrs else 'v',
            return_type=returns, authenticated_execute=callable_by_member, anon_execute=False)
    return after


def comparable(value):
    value = json.loads(json.dumps(value))
    for row in value['routines'].values():
        row.pop('definition', None)
    return value


def comparison_sql(expected, label):
    literal = json.dumps(comparable(expected), ensure_ascii=False, separators=(',', ':'))
    if '$insurance_expected$' in literal:
        raise ValueError('unexpected SQL delimiter in inventory')
    # Exclude function definition display formatting; exact prosrc hash is compared instead.
    inventory = INVENTORY.read_text().strip().rstrip(';')
    return """do $insurance_guard$
declare actual jsonb; expected jsonb := $insurance_expected$%s$insurance_expected$::jsonb; k text;
begin
 select inventory into actual from (%s) observed;
 for k in select jsonb_object_keys(actual->'routines') loop
  actual:=jsonb_set(actual,array['routines',k],(actual#>array['routines',k])-'definition');
 end loop;
 if actual is distinct from expected then
  raise exception 'Insurance reference %s inventory differs; re-observe without retrying blindly';
 end if;
end $insurance_guard$;
""" % (literal, inventory, label)


def generate(snapshot_path, output):
    before = json.loads(snapshot_path.read_text())
    if before.get('schema') != 1 or before.get('metadata_rows') != 0 or before.get('metadata_history_rows') != 0:
        raise ValueError('fresh unused reference observation required')
    if not before['roles']['authenticated_tax_usage'] or not before['roles']['authenticated_public_usage']:
        raise ValueError('existing schema access prerequisite missing')
    if any(r['present'] for r in before['routines'].values() if r['is_new']):
        raise ValueError('new routines already present; do not reinstall')
    candidate = CANDIDATE.read_text()
    after = expected_after(before, candidate)
    output.mkdir(parents=True, exist_ok=False)
    protected = sorted(before['tables'], key=lambda key: int(before['tables'][key]['oid']))
    if len(protected) != 7 or any(not re.fullmatch(r'[a-z_]+\.[a-z_]+', name) for name in protected):
        raise ValueError('protected table inventory differs')
    begin = "begin;\nset local lock_timeout='5s';\nset local statement_timeout='30s';\n" + ''.join('lock table ' + table + ' in share mode;\n' for table in protected)
    body = re.sub(r'(?m)^begin;\s*$', '', candidate, count=1)
    body = re.sub(r'(?m)^commit;\s*$', '', body, count=1)
    install = begin + comparison_sql(before, 'before') + body + '\n' + comparison_sql(after, 'after') + 'commit;\n'
    restore = begin + comparison_sql(after, 'unused-restore-before')
    # The exact after snapshot has metadata row counts 0, so an actually used installation cannot be undone this way.
    for identity, routine in before['routines'].items():
        if not routine['is_new'] and after['routines'][identity]['source_md5'] != routine['source_md5']:
            restore += routine['definition'].strip().rstrip(';') + ';\n'
    drop_order = [
        'public.read_worker_payroll_insurance_income_history(uuid,uuid,date,date)',
        'public.read_worker_payroll_tax_conditions_with_insurance_reference(uuid,uuid)',
        'payroll_tax_private.conditions_save_reply(uuid,uuid,boolean)',
        'payroll_tax_private.verify_basis_reference(uuid,uuid,jsonb)',
        'payroll_tax_private.insurance_income_history(uuid,uuid,date,date)',
        'payroll_tax_private.validate_basis_reference(jsonb)']
    restore += ''.join('drop function ' + identity + ';\n' for identity in drop_order)
    restore += comparison_sql(before, 'unused-restore-after') + 'commit;\n'
    files = {
        'private-prepared-install.sql.review-only': install,
        'private-postflight.read-only.sql': 'begin read only;\n' + comparison_sql(after, 'postflight') + 'commit;\n',
        'private-unused-source-restore.sql.review-only': restore,
        'private-expected-after.json': json.dumps(comparable(after), ensure_ascii=False, indent=2) + '\n'}
    manifest = dict(schema=1, prepared_only=True, production_connected=False,
                    deployment_performed=False, conversion_performed=False, unused_restore_only=True,
                    source_snapshot_sha256=hashlib.sha256(snapshot_path.read_bytes()).hexdigest(),
                    candidate_sha256=hashlib.sha256(candidate.encode()).hexdigest(), artifacts={})
    for name, content in files.items():
        target = output / name
        target.write_text(content)
        target.chmod(0o600)
        manifest['artifacts'][name] = dict(sha256=hashlib.sha256(content.encode()).hexdigest(), bytes=len(content.encode()))
    (output / 'prepare-status.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps(manifest))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('snapshot', type=pathlib.Path)
    parser.add_argument('output', type=pathlib.Path)
    args = parser.parse_args()
    generate(args.snapshot, args.output)
