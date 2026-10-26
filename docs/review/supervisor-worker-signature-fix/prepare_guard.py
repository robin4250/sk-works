"""Wrap the reviewed trigger-only fix with current catalog and row guards."""
import argparse
import hashlib
import json
from pathlib import Path


def literal(value):
    return "'" + value.replace("'", "''") + "'"


def json_literal(value):
    return literal(json.dumps(value, ensure_ascii=False, separators=(",", ":"))) + "::jsonb"


def compose(snapshot, body):
    out = ["-- REVIEW ONLY. Root applies after CI and durable backup; no signature/data repair.",
           "begin;", "set local lock_timeout='5s';", "set local statement_timeout='45s';",
           "lock table public.daily_reports,public.daily_report_workers in access exclusive mode;",
           "do $source_guard$ begin",
           "if current_user<>'postgres' then raise exception 'supervisor_worker_operator_changed';end if;"]
    for r in snapshot["routines"]:
        acl = "null" if r["acl"] is None else literal(r["acl"])
        config = "null" if r["config"] is None else json_literal(r["config"])
        out.append("if not exists(select 1 from pg_proc p where p.oid=to_regprocedure(" + literal(r["signature"]) +
                   ") and p.oid::text=" + literal(r["oid"]) + " and pg_get_functiondef(p.oid)=" + literal(r["definition"]) +
                   " and pg_get_userbyid(p.proowner)=" + literal(r["owner"]) + " and p.proacl::text is not distinct from " + acl +
                   " and to_jsonb(p.proconfig) is not distinct from " + config + " and p.prosecdef=" + str(r["security_definer"]).lower() +
                   " and p.provolatile=" + literal(r["volatility"]) + ")then raise exception 'supervisor_worker_dependency_changed';end if;")
    out.append("if (select jsonb_agg(jsonb_build_object('table',c.relname,'name',t.tgname,'oid',t.oid::text,'enabled',t.tgenabled,'definition',pg_get_triggerdef(t.oid))order by c.relname,t.tgname)from pg_trigger t join pg_class c on c.oid=t.tgrelid where t.tgrelid=any(array['public.daily_report_workers'::regclass,'public.daily_reports'::regclass])and not t.tgisinternal)is distinct from " + json_literal(snapshot["triggers"]) + " then raise exception 'supervisor_worker_triggers_changed';end if;")
    out.append("if (select jsonb_agg(jsonb_build_object('name',c.relname,'oid',c.oid::text,'owner',pg_get_userbyid(c.relowner),'acl',c.relacl::text,'rls',c.relrowsecurity,'columns',(select jsonb_agg(jsonb_build_array(a.attnum,a.attname,a.atttypid::text,a.attnotnull)order by a.attnum)from pg_attribute a where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped))order by c.relname)from pg_class c where c.oid=any(array['public.daily_report_workers'::regclass,'public.daily_reports'::regclass]))is distinct from " + json_literal(snapshot["tables"]) + " then raise exception 'supervisor_worker_tables_changed';end if;")
    out += ["end $source_guard$;", "create temporary table supervisor_worker_protected(relation text primary key,n bigint,h text)on commit drop;", "do $before_rows$ declare target text;n bigint;h text;begin foreach target in array array['public.daily_reports','public.daily_report_workers','public.attendance_entries','public.payroll_statements','public.invoices','public.invoice_detail_lines']loop execute format($digest$select count(*)::bigint,md5(coalesce(string_agg(row_hash,''order by row_hash),''))from(select md5(to_jsonb(x)::text)row_hash from %s x)d$digest$,target)into n,h;insert into pg_temp.supervisor_worker_protected values(target,n,h);end loop;end $before_rows$;", body,
            "do $after_rows$ declare original record;n bigint;h text;begin for original in select * from pg_temp.supervisor_worker_protected loop execute format($digest$select count(*)::bigint,md5(coalesce(string_agg(row_hash,''order by row_hash),''))from(select md5(to_jsonb(x)::text)row_hash from %s x)d$digest$,original.relation)into n,h;if n is distinct from original.n or h is distinct from original.h then raise exception 'supervisor_worker_business_rows_changed';end if;end loop;end $after_rows$;", "commit;"]
    return "\n".join(out) + "\n"


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--snapshot", type=Path, required=True)
    p.add_argument("--body", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    args = p.parse_args()
    sql = compose(json.loads(args.snapshot.read_text())[0]["snapshot"], args.body.read_text())
    args.output.write_text(sql)
    print(json.dumps({"sha256": hashlib.sha256(sql.encode()).hexdigest(), "bytes": len(sql.encode())}))
