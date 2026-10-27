"""Build review-only SQL. Never connect to or modify production."""
from pathlib import Path
import re

here = Path(__file__).resolve().parent
policies = (here / 'policy.sql.review-only').read_text()
assert policies.startswith('-- Candidate only.') and policies.rstrip().endswith('commit;')
policies = re.sub(r'^begin;\s*', '', policies, count=1, flags=re.MULTILINE)
policies = re.sub(r'commit;\s*$', '', policies)
guard = (here / 'delete-preserve.sql.review-only').read_text()
prefix = r'''-- Review-only; root applies only after current CI and backup verification.
begin;
set local search_path='';
set local lock_timeout='5s';
set local statement_timeout='45s';
lock table public.qualification_master,public.qualification_master_aliases,public.worker_qualifications,private.qualification_submissions,public.company_members in share row exclusive mode;
do $guard$ begin
  if current_user <> 'postgres' then raise exception 'wrong_operator'; end if;
  if md5(coalesce((select jsonb_agg(to_jsonb(p) order by policyname)::text from pg_policies p where schemaname='public' and tablename='qualification_master'),'[]')) <> 'd715335814ec7db55087289953b4ce02' then raise exception 'policy_drift'; end if;
  if md5(coalesce((select jsonb_agg(jsonb_build_object('name',conname,'rel',conrelid::regclass::text,'def',pg_get_constraintdef(oid)) order by conname)::text from pg_constraint where confrelid='public.qualification_master'::regclass),'[]')) <> '2a280241e183f7db08cc711c9197b092' then raise exception 'foreign_key_drift'; end if;
  if exists(select 1 from pg_trigger where tgrelid='public.qualification_master'::regclass and not tgisinternal) then raise exception 'trigger_drift'; end if;
  if to_regprocedure('private.guard_qualification_master_manager_company_move()') is not null or to_regprocedure('private.guard_qualification_master_references()') is not null then raise exception 'function_exists'; end if;
end $guard$;
create temporary table qualification_guard_rows(rel text primary key,n bigint,h text) on commit drop;
do $guard$ declare t text; n bigint; h text; begin
  foreach t in array array['public.qualification_master','public.qualification_master_aliases','public.worker_qualifications','private.qualification_submissions','public.company_members'] loop
    execute format($q$select count(*)::bigint,md5(coalesce(string_agg(h,'' order by h),'')) from (select md5(to_jsonb(x)::text) h from %s x) a$q$,t) into n,h;
    insert into pg_temp.qualification_guard_rows values(t,n,h);
  end loop;
end $guard$;
'''
suffix = r'''
do $guard$ declare r record; n bigint; h text; begin
  if (select md5(prosrc) from pg_proc where oid=to_regprocedure('private.guard_qualification_master_manager_company_move()')) <> '807cdfef283e2fef7725b1b9bdd9683d' then raise exception 'move_guard_mismatch'; end if;
  if (select md5(prosrc) from pg_proc where oid=to_regprocedure('private.guard_qualification_master_references()')) <> '163c9463866c34d29a96a499853b1544' then raise exception 'delete_guard_mismatch'; end if;
  if md5(coalesce((select jsonb_agg(to_jsonb(p) order by policyname)::text from pg_policies p where schemaname='public' and tablename='qualification_master' and policyname not in ('managers can update qualification master','managers can delete qualification master')),'[]')) <> 'd715335814ec7db55087289953b4ce02' then raise exception 'existing_policy_changed'; end if;
  for r in select * from pg_temp.qualification_guard_rows loop
    execute format($q$select count(*)::bigint,md5(coalesce(string_agg(h,'' order by h),'')) from (select md5(to_jsonb(x)::text) h from %s x) a$q$,r.rel) into n,h;
    if n<>r.n or h<>r.h then raise exception 'business_rows_changed'; end if;
  end loop;
end $guard$;
commit;
'''
(here / 'root-install.guarded.sql.review-only').write_text(prefix + policies + guard + suffix)
