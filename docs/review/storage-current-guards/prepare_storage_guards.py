"""Prepare reviewed Storage deltas from exact catalog snapshots. Never connects."""
import argparse
import hashlib
import json
import re
from pathlib import Path

FEATURE_SHA = "d01576e8687e7ce053776a64ae51c0603408099dc1e2c3d7752afbff0f7a51db"
LIVE_SHA = "3ba6741327067f4af15ee7169a6e844d60dbb3224885d576995e63b8d94b8f6b"


def lit(value):
    return "'" + value.replace("'", "''") + "'"


def jsonlit(value):
    return lit(json.dumps(value, separators=(",", ":"), ensure_ascii=False)) + "::jsonb"


POLICIES_QUERY = """select coalesce(jsonb_agg(jsonb_build_object('table',tablename,'name',policyname,'roles',to_jsonb(roles),'cmd',cmd,'qual',qual,'with_check',with_check,'permissive',permissive) order by policyname),'[]'::jsonb) from pg_policies where schemaname='storage' and tablename='objects'"""
RELATION_QUERY = """select jsonb_build_object('owner',pg_get_userbyid(c.relowner),'acl',c.relacl::text,'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity) from pg_class c where c.oid='storage.objects'::regclass"""
SCHEMA_QUERY = """select jsonb_build_object('owner',pg_get_userbyid(nspowner),'acl',nspacl::text) from pg_namespace where nspname='storage'"""
COLUMNS_QUERY = """select jsonb_agg(jsonb_build_object('name',attname,'type',format_type(atttypid,atttypmod),'not_null',attnotnull) order by attnum) from pg_attribute where attrelid='storage.objects'::regclass and attnum>0 and not attisdropped"""


def catalog_guard(policies, routines, catalog):
    expected = sorted((p for p in policies if p["table"] == "objects"), key=lambda p: p["name"])
    relation = {k: catalog["relation"][k] for k in ("owner", "acl", "rls", "force_rls")}
    conditions = [
        (POLICIES_QUERY, expected, "policies"),
        (RELATION_QUERY, relation, "relation"),
        (SCHEMA_QUERY, catalog["schema"], "schema"),
        (COLUMNS_QUERY, catalog["object_columns"], "columns"),
    ]
    sql = "do $storage_source_guard$ begin\n"
    for query, value, label in conditions:
        sql += " if (" + query + ") is distinct from " + jsonlit(value) + " then raise exception 'storage_review_" + label + "_drift';end if;\n"
    for routine in routines:
        signature = routine["signature"]
        config_sql = jsonlit(routine["config"]) if routine["config"] is not None else "null"
        sql += " if not exists(select 1 from pg_proc p where p.oid=to_regprocedure(" + lit(signature) + ") and pg_get_functiondef(p.oid)=" + lit(routine["definition"]) + " and pg_get_userbyid(p.proowner)=" + lit(routine["owner"]) + " and p.proacl::text is not distinct from " + (lit(routine["acl"]) if routine["acl"] is not None else "null") + " and to_jsonb(p.proconfig) is not distinct from " + config_sql + " and p.prosecdef=" + str(routine["security_definer"]).lower() + " and p.provolatile=" + lit(routine["volatility"]) + ") then raise exception 'storage_review_helper_drift';end if;\n"
    return sql + "end $storage_source_guard$;\n"


def envelope(guard, body):
    return "-- REVIEW ONLY. No deployment/activation is performed by this generator.\nbegin;\nset local lock_timeout='5s';\nset local statement_timeout='45s';\nlock table storage.objects in share mode;\n" + guard + body + "\ncommit;\n"


def source_body(source_root, name, expected):
    raw = (source_root / "tool/security" / name).read_bytes()
    if hashlib.sha256(raw).hexdigest() != expected:
        raise ValueError("reviewed_storage_source_drift:" + name)
    text = raw.decode().rstrip() + "\n"
    start = text.index("begin;\n")
    if not text.endswith("commit;\n") or text.count("\nbegin;\n") != 1:
        raise ValueError("reviewed_transaction_envelope_drift")
    return text[start + len("begin;\n"):-len("commit;\n")]


def install(kind, source_root, policies, routines, catalog):
    guard = catalog_guard(policies, routines, catalog)
    if kind == "feature":
        body = source_body(source_root, "storage_session_feature_boundary.sql.review-only", FEATURE_SHA)
    elif kind == "live":
        guard += "do $absence$ begin if to_regclass('private.storage_session_guard_rollout') is not null or to_regclass('private.storage_session_guard_installation') is not null or to_regprocedure('private.worker_storage_session_allowed()') is not null or exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='worker_document_live_session_guard') then raise exception 'storage_live_guard_already_present';end if;end $absence$;\n"
        body = source_body(source_root, "storage_session_guard.sql.review-only", LIVE_SHA)
        body += """create table private.storage_session_guard_installation(singleton boolean primary key check(singleton),initial_rollout_xmin text not null);
alter table private.storage_session_guard_installation enable row level security;
revoke all on private.storage_session_guard_installation from public,anon,authenticated,service_role;
insert into private.storage_session_guard_installation select true,xmin::text from private.storage_session_guard_rollout where singleton;
"""
        body += "do $off$ begin if (select count(*) from private.storage_session_guard_rollout)<>1 or exists(select 1 from private.storage_session_guard_rollout where enabled) then raise exception 'storage_live_not_unused_off';end if;end $off$;\n"
    else:
        raise ValueError("unknown module")
    return envelope(guard, body)


def restore(kind, source_root, before_policies, post_policies, routines, catalog):
    guard = catalog_guard(post_policies, routines, catalog)
    if kind == "feature":
        old = next(p for p in before_policies if p["name"] == "worker_document_photo_managed_read")
        body = "-- MANUAL EMERGENCY ONLY: this deliberately reopens the original manager feature-OFF read.\nalter policy worker_document_photo_managed_read on storage.objects using (" + old["qual"] + ");\n"
    elif kind == "live":
        raw = source_body(source_root, "storage_session_guard.sql.review-only", LIVE_SHA)
        match = re.search(r"\bas \$\$(.*?)\$\$;", raw, re.S)
        if match is None:
            raise ValueError("reviewed_live_function_delimiter_drift")
        expected_body = match.group(1)
        md5 = hashlib.md5(expected_body.encode()).hexdigest()
        body = """do $unused$ begin
 if (select count(*) from private.storage_session_guard_rollout)<>1 or exists(select 1 from private.storage_session_guard_rollout where enabled) then raise exception 'storage_live_restore_requires_off';end if;
 if (select count(*) from private.storage_session_guard_installation)<>1 or not exists(select 1 from private.storage_session_guard_rollout r join private.storage_session_guard_installation i using(singleton) where r.xmin::text=i.initial_rollout_xmin) then raise exception 'storage_live_restore_requires_unused';end if;
 if not exists(select 1 from pg_proc p where p.oid=to_regprocedure('private.worker_storage_session_allowed()') and md5(p.prosrc)='""" + md5 + """' and pg_get_userbyid(p.proowner)='postgres' and p.prosecdef and p.provolatile='s' and p.proconfig=array['search_path=""']::text[] and p.proacl::text='{postgres=X/postgres,authenticated=X/postgres}') then raise exception 'storage_live_restore_helper_drift';end if;
 if not exists(select 1 from pg_class c where c.oid=to_regclass('private.storage_session_guard_rollout') and pg_get_userbyid(c.relowner)='postgres' and c.relrowsecurity and not has_table_privilege('anon',c.oid,'select') and not has_table_privilege('authenticated',c.oid,'select') and not has_table_privilege('service_role',c.oid,'select')) then raise exception 'storage_live_restore_table_drift';end if;
 if not exists(select 1 from pg_class c where c.oid=to_regclass('private.storage_session_guard_installation') and pg_get_userbyid(c.relowner)='postgres' and c.relrowsecurity and not exists(select 1 from aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a where a.grantee<>c.relowner)) then raise exception 'storage_live_restore_installation_drift';end if;
 if (select count(*) from pg_attribute where attrelid='private.storage_session_guard_installation'::regclass and attnum>0 and not attisdropped)<>2 or (select count(*) from pg_index where indrelid='private.storage_session_guard_installation'::regclass)<>1 then raise exception 'storage_live_restore_installation_shape_drift';end if;
end $unused$;
drop policy worker_document_live_session_guard on storage.objects;
drop function private.worker_storage_session_allowed();
drop table private.storage_session_guard_rollout;
drop table private.storage_session_guard_installation;
"""
    else:
        raise ValueError("unknown module")
    return envelope(guard, body)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--policies", type=Path, required=True)
    parser.add_argument("--routines", type=Path, required=True)
    parser.add_argument("--catalog", type=Path, required=True)
    parser.add_argument("--kind", choices=("feature", "live"), required=True)
    parser.add_argument("--post-policies", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    policies = json.loads(args.policies.read_text())[0]["policies"]
    routines = json.loads(args.routines.read_text())[0]["routines"]
    catalog = json.loads(args.catalog.read_text())[0]["catalog"]
    if args.post_policies:
        post = json.loads(args.post_policies.read_text())[0]["policies"]
        sql = restore(args.kind, args.source_root, policies, post, routines, catalog)
    else:
        sql = install(args.kind, args.source_root, policies, routines, catalog)
    args.output.write_text(sql)
    print(json.dumps({"output": str(args.output), "sha256": hashlib.sha256(sql.encode()).hexdigest(), "deployment_performed": False}))


if __name__ == "__main__":
    main()
