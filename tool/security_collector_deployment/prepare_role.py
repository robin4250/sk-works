#!/usr/bin/env python3
"""Offline stage-one role-only preparation. NO connection, login or deployment."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
ROLE = 'sko_security_collector_ingest'
SPEC = dict(rolname=ROLE, rolsuper=False, rolinherit=False, rolcreaterole=False,
            rolcreatedb=False, rolcanlogin=False, rolreplication=False,
            rolbypassrls=False, rolconnlimit=-1, rolvaliduntil=None, rolconfig=None)
INVENTORY = (ROOT/'role_inventory.read-only.sql').read_text().strip().rstrip(';')


def canonical(value):
    result = json.loads(json.dumps(value))
    if result.get('role') is not None:
        result['role'].pop('oid', None)
    return result


def validate(value):
    if set(value) != {'schema','operator','role','credential_absent','memberships','dependencies'} or value['schema'] != 1:
        raise ValueError('exact role observation required')
    if value['credential_absent'] is not True or value['memberships'] != 0 or value['dependencies'] != 0:
        raise ValueError('bridge role already credentialed, connected or used')
    role = canonical(value)['role']
    if role is not None and role != SPEC:
        raise ValueError('existing bridge role attributes differ; never weaken it')


def guard(expected, label):
    literal = json.dumps(canonical(expected), separators=(',', ':'))
    if '$role_expected$' in literal:
        raise ValueError('unexpected SQL delimiter')
    return """do $role_guard$
declare actual jsonb; expected jsonb := $role_expected$%s$role_expected$::jsonb;
begin
 select inventory into actual from (%s) observed;
 if actual->'role'<>'null'::jsonb then actual:=jsonb_set(actual,'{role}',(actual->'role')-'oid');end if;
 if actual is distinct from expected then raise exception 'Collector bridge %s differs; no automatic retry';end if;
end $role_guard$;
""" % (literal, INVENTORY, label)


def prepare(snapshot, output):
    before = json.loads(Path(snapshot).read_text())
    validate(before)
    after = dict(schema=1, operator=before['operator'],role=SPEC, credential_absent=True, memberships=0, dependencies=0)
    # These locks also prevent GRANT/dependency races across unused checks.
    # Managed production may refuse system-catalog locks/CREATE ROLE: that is a
    # prerequisite failure, not permission to remove the lock or borrow an owner.
    begin = "begin;set local search_path='';set local lock_timeout='3s';set local statement_timeout='30s';\n"
    begin += "lock table pg_catalog.pg_authid,pg_catalog.pg_auth_members,pg_catalog.pg_shdepend in share row exclusive mode;\n"
    install = begin + guard(before, 'before')
    if before['role'] is None:
        install += 'create role '+ROLE+' NOLOGIN NOINHERIT NOSUPERUSER NOCREATEROLE NOCREATEDB NOREPLICATION NOBYPASSRLS CONNECTION LIMIT -1 PASSWORD NULL;\n'
    install += guard(after, 'after') + 'commit;\n'
    restore = begin + guard(after, 'unused-restore-before')
    if before['role'] is None:
        restore += 'drop role '+ROLE+';\n' + guard(before, 'unused-restore-after') + 'commit;\n'
    else:
        restore += "do $$begin raise exception 'Pre-existing role is not owned by this installation; removal prohibited';end$$;\nrollback;\n"
    contents = {'private-role-install.sql.review-only':install,
        'private-role-postflight.read-only.sql':'begin read only;'+guard(after,'postflight')+'commit;\n',
        'private-role-unused-restore.sql.review-only':restore}
    out = Path(output);out.mkdir(parents=True, exist_ok=False);out.chmod(0o700)
    manifest = dict(schema=1, stage='bridge_role_only', prepared_only=True,
        deployment_performed=False, production_connected=False, credentials_created=False,
        membership_grants=False, business_data_mutations=False,
        existing_role_preserved=before['role'] is not None,
        managed_production_permissions_proven=False,
        snapshot_sha256=hashlib.sha256(Path(snapshot).read_bytes()).hexdigest(), artifacts={})
    if before['operator'].get('rolsuper') is not True:
        # PostgreSQL17 CREATEROLE adds creator ADMIN membership; catalog locks
        # may also require elevated managed privileges. Do not manufacture a
        # membership exception or suggest SET/INHERIT to make production pass.
        manifest['blockers']=['managed_non_superuser_role_provision_not_proven_membership_zero_required']
        status=out/'prepare-status.json';status.write_text(json.dumps(manifest,indent=2)+'\n');status.chmod(0o600)
        return manifest
    for name, content in contents.items():
        target=out/name;target.write_text(content);target.chmod(0o600)
        manifest['artifacts'][name]=hashlib.sha256(content.encode()).hexdigest()
    status=out/'prepare-status.json';status.write_text(json.dumps(manifest, indent=2)+'\n');status.chmod(0o600)
    return manifest


if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('snapshot',type=Path);p.add_argument('output',type=Path)
    args=p.parse_args();print(json.dumps(prepare(args.snapshot,args.output)))
