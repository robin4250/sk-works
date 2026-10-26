#!/usr/bin/env python3
"""Offline collector-only assembly. No connection, role provisioning or activation."""
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent
CHANGED = ['private.reauthentication_scope(text)', 'private.issue_reauthentication_proof(uuid,uuid,text,jsonb,text)']
NS = 'security_collector_connection_private'


def lit(value):
    return "'" + value.replace("'", "''") + "'"


def body(definition):
    match = re.search(r'AS (\$[\w]*\$)([\s\S]*?)\1', definition, re.I)
    if not match:
        raise ValueError('Function dollar body required')
    return match[2]


def transaction_body(sql):
    starts = list(re.finditer(r'^begin;\s*$', sql, re.M))
    ends = list(re.finditer(r'^commit;\s*$', sql, re.M))
    assert len(starts) == len(ends) == 1
    assert not sql[ends[0].end():].strip()
    return sql[starts[0].end():ends[0].start()]


def main():
    originals = json.loads((ROOT / 'sources/current-core-originals.json').read_text())
    by_sig = {r['signature']: r for r in originals}
    definitions = {}
    for signature in CHANGED:
        definitions[signature] = by_sig[signature]['definition']
    old = "  when 'attendance.manage' then 'attendance_management' end"
    assert definitions[CHANGED[0]].count(old) == 1
    definitions[CHANGED[0]] = definitions[CHANGED[0]].replace(old,
        "  when 'attendance.manage' then 'attendance_management'\n  when 'master.security_collector.read' then 'master_security' end")
    old = " elsif p_operation='master.security_incidents.read' and p_target<>'{\"scope\":\"platform\"}'::jsonb then"
    assert definitions[CHANGED[1]].count(old) == 1
    definitions[CHANGED[1]] = definitions[CHANGED[1]].replace(old,
        " elsif p_operation='master.security_collector.read' and p_target is distinct from '{\"scope\":\"decoy_collector\"}'::jsonb then\n  raise sqlstate '42501' using message='reauthentication_unavailable';\n" + old)
    guards = []
    for r in originals:
        assert hashlib.md5(body(r['definition']).encode()).hexdigest() == r['body_md5']
        guards.append("if not exists(select 1 from pg_proc p where p.oid=to_regprocedure(%s) and md5(p.prosrc)=%s and pg_get_userbyid(p.proowner)=%s and p.proacl::text is not distinct from %s and to_jsonb(p.proconfig) is not distinct from %s::jsonb and p.prosecdef=%s and p.provolatile=%s) then raise exception 'collector_core_original_changed: %s';end if;" % (
            lit(r['signature']), lit(r['body_md5']), lit(r['owner']), lit(r['acl']), lit(json.dumps(r['config'])), str(r['security_definer']).lower(), lit(r['volatility']), r['signature']))
    prefix = """-- REVIEW ONLY. Collector-only addition to existing four-scope core. No role/key/gate provisioning.
begin;
set local search_path='';set local lock_timeout='5s';set local statement_timeout='45s';
lock table private.reauthentication_rollout,private.reauthentication_proofs in share row exclusive mode;
do $before$ begin
 if current_user<>'postgres' or to_regnamespace('security_collector_connection_private') is not null then raise exception 'collector_connection_precondition';end if;
 if (select array_agg(scope order by scope) from private.reauthentication_rollout) is distinct from array['attendance_management','master_feature','master_security','secondary_password']::text[] or exists(select 1 from private.reauthentication_rollout where scope='master_security' and enabled) then raise exception 'collector_current_core_four_scopes_required_off';end if;
""" + '\n'.join(guards) + "\nend $before$;\n"
    prefix += """create schema security_collector_connection_private;
revoke all on schema security_collector_connection_private from public,anon,authenticated,service_role;
create table security_collector_connection_private.originals(signature text primary key,definition text not null,metadata jsonb not null);
create table security_collector_connection_private.installation(singleton boolean primary key check(singleton),private_acl text,rollout jsonb not null);
alter table security_collector_connection_private.originals enable row level security;
alter table security_collector_connection_private.installation enable row level security;
revoke all on all tables in schema security_collector_connection_private from public,anon,authenticated,service_role;
insert into security_collector_connection_private.installation values(true,(select nspacl::text from pg_namespace where nspname='private'),(select jsonb_agg(to_jsonb(x) order by scope) from private.reauthentication_rollout x));
"""
    prefix += "insert into security_collector_connection_private.originals select x,pg_get_functiondef(p.oid),to_jsonb(p) from unnest(array[%s])x join pg_proc p on p.oid=to_regprocedure(x);\n" % ','.join(map(lit, CHANGED))
    storage = (ROOT / 'sources/security_collector_storage_v1_20261020.sql.review-only').read_text()
    reader = (ROOT / 'sources/collector_public_read.sql').read_text()
    assert hashlib.sha256(storage.encode()).hexdigest() == 'b96f6e4365e2e992886f38dad0f777e55665f18b03525cddf4edbdf746348207'
    assert hashlib.sha256(reader.encode()).hexdigest() == '2e3e5dd51c24d9f8c9553aec67a758f6ab7b9480fa6d6b8b6e01ee12bbe96f1a'
    # Reuse the original metadata validator/dedupe body, but expose no bridge role.
    storage_unit = transaction_body(storage)
    storage_unit = storage_unit[storage_unit.index('create table private.security_collector_control('):storage_unit.index('-- Custom default privileges')]
    storage_unit = storage_unit.replace(',sko_security_collector_ingest', '')
    storage_unit = storage_unit.replace('grant usage on schema private to sko_security_collector_ingest;\n','')
    storage_unit = storage_unit.replace('grant execute on function private.ingest_security_collector_event(jsonb) to sko_security_collector_ingest;\n','')
    marker = " select coalesce(jsonb_agg(x),'[]'::jsonb) into result from ("
    assert storage_unit.count(marker) == 1
    storage_unit = storage_unit.replace(marker, " if exists(select 1 from private.security_collector_events e where received_at>=clock_timestamp()-interval '7 days' and not private.verify_collector_event_evidence(e.event_id)) then raise exception 'collector_evidence_integrity_failed' using errcode='55000';end if;\n"+marker)
    read_body = re.search(r'create function private.read_security_collector_events[\s\S]*?as (\$[\w]*\$)([\s\S]*?)\1', storage_unit, re.I)[2]
    reader_unit = transaction_body(reader).replace(',sko_security_collector_ingest','').replace('a62cc46b5c9fbcee3e38e9699e44bd00',hashlib.md5(read_body.encode()).hexdigest())
    roleless = (ROOT/'roleless-core.sql').read_text()
    patched = '\n'.join(definitions[s].rstrip().rstrip(';')+';' for s in CHANGED)
    post = """do $preserved$ begin
 if (select jsonb_agg(to_jsonb(x) order by scope) from private.reauthentication_rollout x) is distinct from (select rollout from security_collector_connection_private.installation) then raise exception 'collector_changed_existing_rollout';end if;
 if exists(select 1 from security_collector_connection_private.originals o join pg_proc p on p.oid=to_regprocedure(o.signature) where to_jsonb(p)-'prosrc' is distinct from o.metadata-'prosrc') then raise exception 'collector_changed_existing_metadata';end if;
 if (select count(*) from security_collector_connection_private.originals)<>2 or exists(select 1 from private.security_collector_control where ingest_enabled or read_enabled) or exists(select 1 from private.security_collector_events) or exists(select 1 from private.security_collector_read_audit) then raise exception 'collector_initial_not_unused_off';end if;
end $preserved$;
commit;
"""
    post = post.replace('end $preserved$;', " if (select nspacl::text from pg_namespace where nspname='private') is distinct from (select private_acl from security_collector_connection_private.installation) then raise exception 'collector_private_schema_acl_changed';end if;\nend $preserved$;")
    object_capture = """create table security_collector_connection_private.new_objects(signature text primary key,metadata jsonb not null);
+alter table security_collector_connection_private.new_objects enable row level security;
+revoke all on security_collector_connection_private.new_objects from public,anon,authenticated,service_role;
+insert into security_collector_connection_private.new_objects select x,to_jsonb(p) from unnest(array[
+'private.ingest_security_collector_event(jsonb)','private.read_security_collector_events(text)','public.master_security_collector_events(text)',
+'private.collector_mac_equal(bytea,bytea)','private.collector_event_metadata(private.security_collector_events)',
+'private.verify_collector_event_evidence(uuid)','public.ingest_signed_security_collector_event(jsonb)','private.purge_expired_security_collector_events()'])x join pg_proc p on p.oid=to_regprocedure(x);
+""".replace('\n+','\n')
    post = post.replace('end $preserved$;', """ if exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace cross join lateral aclexplode(coalesce(c.relacl,acldefault(case when c.relkind='S' then 'S'::\"char\" else 'r'::\"char\" end,c.relowner)))a where (n.nspname='security_collector_connection_private' or(n.nspname='private' and c.relname like 'security_collector_%')) and c.relkind in('r','S') and(a.grantee<>c.relowner or(c.relkind='r' and not c.relrowsecurity))) then raise exception 'collector_relation_security_changed';end if;
 if exists(select 1 from security_collector_connection_private.new_objects o join pg_proc p on p.oid=to_regprocedure(o.signature) cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner)))a where a.grantee<>p.proowner and not(a.privilege_type='EXECUTE' and not a.is_grantable and ((o.signature in('private.read_security_collector_events(text)','public.master_security_collector_events(text)') and a.grantee='authenticated'::regrole)or(o.signature='public.ingest_signed_security_collector_event(jsonb)' and a.grantee='service_role'::regrole)))) then raise exception 'collector_routine_acl_changed';end if;
end $preserved$;""")
    install = prefix + patched + '\n' + storage_unit + '\n' + roleless + '\n' + reader_unit + '\n' + object_capture + post
    new_hashes = {s: hashlib.md5(body(definitions[s]).encode()).hexdigest() for s in CHANGED}
    restore = """-- REVIEW ONLY. Unused collector-only restore; never removes existing core or role.
begin;
set local search_path='';set local lock_timeout='5s';set local statement_timeout='45s';
lock table private.reauthentication_rollout,private.reauthentication_proofs in share row exclusive mode;
lock table private.security_collector_control,private.security_collector_events,private.security_collector_read_audit,private.security_collector_keys,private.security_collector_evidence,private.security_collector_retention_audit,security_collector_connection_private.originals,security_collector_connection_private.installation,security_collector_connection_private.new_objects in access exclusive mode;
do $unused$ declare x record;begin
 if current_user<>'postgres' or (select count(*) from security_collector_connection_private.originals)<>2 or (select count(*) from security_collector_connection_private.installation)<>1 then raise exception 'collector_unused_restore_precondition';end if;
 if exists(select 1 from private.security_collector_control where ingest_enabled or read_enabled) or exists(select 1 from private.security_collector_events) or exists(select 1 from private.security_collector_read_audit) or exists(select 1 from private.security_collector_read_audit_audit_id_seq where is_called or last_value<>1) or exists(select 1 from private.security_collector_keys) or exists(select 1 from private.security_collector_evidence) or exists(select 1 from private.security_collector_retention_audit) or exists(select 1 from private.security_collector_retention_audit_audit_id_seq where is_called or last_value<>1) or exists(select 1 from private.reauthentication_proofs where operation='master.security_collector.read') then raise exception 'collector_used_restore_refused';end if;
 if exists(select 1 from security_collector_connection_private.originals o join pg_proc p on p.oid=to_regprocedure(o.signature) where to_jsonb(p)-'prosrc' is distinct from o.metadata-'prosrc') then raise exception 'collector_restore_core_metadata_changed';end if;
 if (select count(*) from security_collector_connection_private.new_objects)<>8 or exists(select 1 from security_collector_connection_private.new_objects o left join pg_proc p on p.oid=to_regprocedure(o.signature) where to_jsonb(p) is distinct from o.metadata) then raise exception 'collector_new_routine_changed';end if;
 if exists(select 1 from pg_proc p where p.oid not in(select to_regprocedure(signature) from security_collector_connection_private.new_objects union all select to_regprocedure(signature)from security_collector_connection_private.originals) and p.prosrc ~* '(security_collector_(keys|events|read_audit|evidence|control|retention_audit)|ingest_signed_security_collector_event|verify_collector_event_evidence|purge_expired_security_collector_events|collector_event_metadata|collector_mac_equal|security_collector_connection_private)') then raise exception 'collector_external_runtime_dependency';end if;
"""
    for s, h in new_hashes.items():
        restore += " if not exists(select 1 from pg_proc where oid=to_regprocedure(%s) and md5(prosrc)=%s) then raise exception 'collector_restore_core_body_changed';end if;\n" % (lit(s), lit(h))
    restore += """ for x in select * from security_collector_connection_private.originals order by signature loop execute x.definition;end loop;
 if exists(select 1 from security_collector_connection_private.originals o join pg_proc p on p.oid=to_regprocedure(o.signature) where to_jsonb(p) is distinct from o.metadata) then raise exception 'collector_original_full_metadata_restore_failed';end if;
end $unused$;
drop function public.master_security_collector_events(text);
drop function private.read_security_collector_events(text);
drop function public.ingest_signed_security_collector_event(jsonb);
drop function private.purge_expired_security_collector_events();
drop function private.verify_collector_event_evidence(uuid);
drop function private.collector_event_metadata(private.security_collector_events);
drop function private.collector_mac_equal(bytea,bytea);
drop function private.ingest_security_collector_event(jsonb);
drop table private.security_collector_evidence;
drop table private.security_collector_keys;
drop table private.security_collector_retention_audit;
drop table private.security_collector_read_audit;
drop table private.security_collector_events;
drop table private.security_collector_control;
do $schema_restored$ begin
 if (select nspacl::text from pg_namespace where nspname='private') is distinct from (select private_acl from security_collector_connection_private.installation) then raise exception 'collector_schema_acl_restore_failed';end if;
end $schema_restored$;
drop table security_collector_connection_private.new_objects;
drop table security_collector_connection_private.originals;
drop table security_collector_connection_private.installation;
drop schema security_collector_connection_private restrict;
commit;
"""
    (ROOT / 'install-off.sql.review-only').write_text(install)
    (ROOT / 'restore-unused.sql.review-only').write_text(restore)
    manifest = {'schema': 1, 'base_main': '74d4c2f578e26ca1f7f21628f19a1da6b2fdeee9', 'changed_core_functions': new_hashes,
        'existing_scopes': ['attendance_management','master_feature','master_security','secondary_password'],
        'role_provisioning': False, 'bridge_role_required': False, 'production_applied': False,
        'artifacts': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [ROOT/'install-off.sql.review-only', ROOT/'restore-unused.sql.review-only']}}
    (ROOT / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps(manifest))


if __name__ == '__main__':
    main()
