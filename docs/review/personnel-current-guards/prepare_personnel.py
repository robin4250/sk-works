"""Review-only current-catalog wrapper around the unchanged P34 composition."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path

COMPOSER_SHA = "954d6ad0952ad8f68d01d87d70deff237842587badf9c96e10abdcb9f21ed9bd"


def lit(s):
    return "'" + s.replace("'", "''") + "'"


def jlit(value):
    return lit(json.dumps(value, ensure_ascii=False, separators=(",", ":"))) + "::jsonb"


def ident(s):
    return '"' + s.replace('"', '""') + '"'


POLICIES = """select coalesce(jsonb_agg(jsonb_build_object('table',tablename,'name',policyname,'permissive',permissive,'roles',to_jsonb(roles),'cmd',cmd,'qual',qual,'with_check',with_check) order by tablename,policyname),'[]'::jsonb) from pg_policies where schemaname='public' and tablename in('worker_personnel_profiles','worker_family_members')"""
TABLES = """select jsonb_agg(jsonb_build_object('relation',c.relname,'oid',c.oid::text,'owner',pg_get_userbyid(c.relowner),'acl',c.relacl::text,'rls',c.relrowsecurity) order by c.relname) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and c.relname in('worker_personnel_profiles','worker_family_members')"""


def guard(snapshot):
    policies = sorted(snapshot["policies"], key=lambda p: (p["table"], p["name"]))
    tables = sorted(snapshot["tables"], key=lambda t: t["relation"])
    sql = "do $personnel_fresh_guard$ begin\n"
    for query, value, key in [(POLICIES, policies, "policies"), (TABLES, tables, "tables")]:
        sql += "if (" + query + ") is distinct from " + jlit(value) + " then raise exception 'personnel_current_" + key + "_drift';end if;\n"
    for r in snapshot["routines"]:
        config = "null" if r["config"] is None else jlit(r["config"])
        acl = "null" if r["acl"] is None else lit(r["acl"])
        sql += "if not exists(select 1 from pg_proc p where p.oid=to_regprocedure(" + lit(r["signature"]) + ") and p.oid::text=" + lit(str(r["oid"])) + " and pg_get_functiondef(p.oid)=" + lit(r["definition"]) + " and pg_get_userbyid(p.proowner)=" + lit(r["owner"]) + " and p.proacl::text is not distinct from " + acl + " and to_jsonb(p.proconfig) is not distinct from " + config + " and p.prosecdef=" + str(r["security_definer"]).lower() + " and p.provolatile=" + lit(r["volatility"]) + ") then raise exception 'personnel_current_routine_drift';end if;\n"
    return sql + "end $personnel_fresh_guard$;\n"


PRE_ROWS = """create temporary table sko_personnel_protected(relation text primary key,n bigint,h text) on commit drop;
do $rows_before$ declare target text;n bigint;h text;begin
 foreach target in array array['public.worker_personnel_profiles','public.worker_family_members'] loop
  execute format($digest$select count(*)::bigint,md5(coalesce(string_agg(row_hash,'' order by row_hash),''))from(select md5(to_jsonb(x)::text)row_hash from %s x)d$digest$,target)into n,h;
  insert into pg_temp.sko_personnel_protected values(target,n,h);
 end loop;
end $rows_before$;
"""
POST_ROWS = """do $rows_after$ declare original record;n bigint;h text;begin
 for original in select * from pg_temp.sko_personnel_protected loop
  execute format($digest$select count(*)::bigint,md5(coalesce(string_agg(row_hash,'' order by row_hash),''))from(select md5(to_jsonb(x)::text)row_hash from %s x)d$digest$,original.relation)into n,h;
  if n is distinct from original.n or h is distinct from original.h then raise exception 'personnel_current_business_rows_changed';end if;
 end loop;
end $rows_after$;
"""


def compose(source_root):
    module_path = source_root / "tool/security/p34_atomic.py"
    if hashlib.sha256(module_path.read_bytes()).hexdigest() != COMPOSER_SHA:
        raise ValueError("p34_composer_source_drift")
    spec = importlib.util.spec_from_file_location("reviewed_p34", module_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    sql = module.compose(source_root)
    if not sql.startswith("begin;\n") or not sql.endswith("commit;\n"):
        raise ValueError("p34_transaction_drift")
    return sql[len("begin;\n"):-len("commit;\n")]


def envelope(snapshot, body):
    return "-- REVIEW ONLY. Root-owned production review and recovery checks remain required.\nbegin;\nset local lock_timeout='5s';\nset local statement_timeout='45s';\nlock table public.worker_personnel_profiles,public.worker_family_members in access exclusive mode;\n" + guard(snapshot) + PRE_ROWS + body + "\n" + POST_ROWS + "commit;\n"


def install(source_root, snapshot):
    return envelope(snapshot, compose(source_root))


def restore(before, post):
    # Read-policy/helper use is not tracked by original P34. This is deliberately
    # emergency source restoration, never an automatic 'unused' assertion.
    body = "-- EMERGENCY ONLY: ordinary access must be stopped/isolated externally.\n-- Restoring these original definitions reopens known manager feature-OFF access.\n"
    for r in before["routines"]:
        if r["signature"] in ("private.employee_personnel_rows()", "private.can_edit_worker_personnel(uuid)"):
            body += r["definition"] + ";\n"
    for p in before["policies"]:
        target = "public." + ident(p["table"])
        body += "drop policy " + ident(p["name"]) + " on " + target + ";\n"
        body += "create policy " + ident(p["name"]) + " on " + target + " as " + p["permissive"] + " for " + p["cmd"] + " to " + ",".join(ident(r) for r in p["roles"])
        if p["qual"] is not None:
            body += " using (" + p["qual"] + ")"
        if p["with_check"] is not None:
            body += " with check (" + p["with_check"] + ")"
        body += ";\n"
    body += guard(before)
    return envelope(post, body)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", required=True, type=Path)
    parser.add_argument("--before", required=True, type=Path)
    parser.add_argument("--post", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    before = json.loads(args.before.read_text())[0]["snapshot"]
    if args.post:
        sql = restore(before, json.loads(args.post.read_text())[0]["snapshot"])
    else:
        sql = install(args.source_root, before)
    args.output.write_text(sql)
    print(json.dumps({"output": str(args.output), "sha256": hashlib.sha256(sql.encode()).hexdigest(), "production_changed": False}))


if __name__ == "__main__":
    main()
