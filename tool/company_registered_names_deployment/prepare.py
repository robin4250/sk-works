#!/usr/bin/env python3
"""Offline exact-state names API install/postflight/unchanged-state restore.

Never connects or deploys. Read-only calls leave no use counter: restore requires
an operator to withdraw client use, in addition to the enforced exact-state guard.
"""
import argparse
import hashlib
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[2]
INVENTORY = pathlib.Path(__file__).with_name('inventory.read-only.sql')
CANDIDATE = ROOT / 'docs/candidates/company_registered_allowance_labels_20261024.sql.review-only'
SOURCE_SHA = '8af1ecca42cb16ae9223206f347cd1ed778da58f1d208ac79762e9e9350f583d'
NEW = {
    'company_common_allowance_private.registered_labels(uuid)': ('44f58a1d685a9cf5e3928b02abccc289', True),
    'public.read_company_registered_allowance_labels(uuid)': ('ff5e008d239b23bb411cd750b0e8ab11', False),
}


def comparable(snapshot):
    value = json.loads(json.dumps(snapshot))
    for item in value['routines'].values():
        item.pop('definition', None)
    return value


def after_snapshot(before, candidate):
    result = json.loads(json.dumps(before))
    pattern = r'create function ([\w.]+)\(([^)]*)\)\s*returns jsonb([\s\S]*?)as (\$[\w]*\$)([\s\S]*?)\4;'
    found = {}
    for name, args, attrs, _, body in re.findall(pattern, candidate, re.I):
        identity = name + '(' + ','.join(x.strip().split()[-1] for x in args.split(',')) + ')'
        digest = hashlib.md5(body.encode()).hexdigest()
        definer = 'security definer' in attrs
        if NEW.get(identity) != (digest, definer) or 'stable' not in attrs or "set search_path=''" not in attrs:
            raise ValueError('reviewed new routine source/attributes changed')
        found[identity] = dict(is_new=True, present=True, source_md5=digest,
            definition=None, owner='postgres', acl=['postgres=X/postgres', 'authenticated=X/postgres'],
            config=['search_path=""'], definer=definer, volatility='s', return_type='jsonb',
            authenticated_execute=True, anon_execute=False, service_execute=False)
    if set(found) != set(NEW):
        raise ValueError('expected exactly two new names routines')
    result['routines'].update(found)
    return result


def guard(expected, label):
    literal = json.dumps(comparable(expected), ensure_ascii=False, separators=(',', ':'))
    if '$names_expected$' in literal:
        raise ValueError('unexpected delimiter')
    inventory = INVENTORY.read_text().strip().rstrip(';')
    return '''do $names_guard$
declare actual jsonb;expected jsonb:=$names_expected$%s$names_expected$::jsonb;k text;
begin
 select inventory into actual from (%s) observed;
 for k in select jsonb_object_keys(actual->'routines') loop
  actual:=jsonb_set(actual,array['routines',k],(actual#>array['routines',k])-'definition');
 end loop;
 if actual is distinct from expected then
  raise exception 'Registered names %s inventory differs; re-observe, do not retry blindly';
 end if;
end $names_guard$;
''' % (literal, inventory, label)


def generate(snapshot, output):
    before = json.loads(snapshot.read_text())
    if before.get('schema') != 1 or set(before['routines']) != set(NEW) | {
        'company_common_allowance_private.session_id()', 'private.account_access_allowed()', 'auth.uid()'}:
        raise ValueError('reviewed routine inventory differs')
    if any(before['routines'][key]['present'] for key in NEW):
        raise ValueError('new names API already present; do not reinstall')
    if not all(row['present'] for key, row in before['routines'].items() if key not in NEW):
        raise ValueError('existing auth/session helper missing')
    if before['roles'] != {'authenticated_private_usage': True, 'authenticated_public_usage': True}:
        raise ValueError('existing member schema usage differs; no schema grant is generated')
    candidate = CANDIDATE.read_text()
    if hashlib.sha256(candidate.encode()).hexdigest() != SOURCE_SHA:
        raise ValueError('reviewed candidate hash changed')
    after = after_snapshot(before, candidate)
    tables = sorted(before['tables'], key=lambda name: int(before['tables'][name]['oid']))
    if len(tables) != 7 or any(not re.fullmatch(r'[a-z_]+\.[a-z_]+', name) for name in tables):
        raise ValueError('protected relation inventory differs')
    begin = "begin;\nset local lock_timeout='5s';\nset local statement_timeout='30s';\n" + ''.join(
        'lock table ' + name + ' in share mode;\n' for name in tables)
    unit = re.sub(r'(?m)^begin;\s*$', '', candidate, count=1)
    unit = re.sub(r'(?m)^commit;\s*$', '', unit, count=1)
    install = begin + guard(before, 'before') + unit + '\n' + guard(after, 'after') + 'commit;\n'
    restore = '-- OPERATOR: withdraw client use first. Reads leave no machine-readable use marker.\n' + begin + guard(after, 'unchanged-state restore before')
    restore += 'drop function public.read_company_registered_allowance_labels(uuid);\n'
    restore += 'drop function company_common_allowance_private.registered_labels(uuid);\n'
    restore += guard(before, 'restored') + 'commit;\n'
    output.mkdir(parents=True, exist_ok=False)
    contents = {
        'private-install.sql.review-only': install,
        'private-postflight.read-only.sql': 'begin read only;\n' + guard(after, 'postflight') + 'commit;\n',
        'private-unchanged-state-restore.sql.review-only': restore,
        'private-expected-after.json': json.dumps(comparable(after), ensure_ascii=False, indent=2) + '\n',
    }
    manifest = dict(schema=1, prepared_only=True, production_connected=False,
        deployment_performed=False, application_data_mutations=False,
        read_use_counter=False, restore_requires_client_withdrawal=True,
        candidate_sha256=SOURCE_SHA, snapshot_sha256=hashlib.sha256(snapshot.read_bytes()).hexdigest(), artifacts={})
    for name, content in contents.items():
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
