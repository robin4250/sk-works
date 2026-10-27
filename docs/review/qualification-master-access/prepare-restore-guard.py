"""Generate restore only with a reviewed post-install catalog fingerprint."""
from pathlib import Path
import argparse
import re

p = argparse.ArgumentParser()
p.add_argument('--expected-installed-catalog-md5', required=True)
args = p.parse_args()
if not re.fullmatch(r'[a-f0-9]{32}', args.expected_installed_catalog_md5):
    p.error('expected installed catalog fingerprint must be 32 lowercase hex digits')
catalog = r'''jsonb_build_object(
  'policies',(select coalesce(jsonb_agg(to_jsonb(p) order by policyname),'[]'::jsonb) from pg_policies p where schemaname='public' and tablename='qualification_master'),
  'triggers',(select coalesce(jsonb_agg(jsonb_build_object('name',tgname,'definition',pg_get_triggerdef(oid)) order by tgname),'[]'::jsonb) from pg_trigger where tgrelid='public.qualification_master'::regclass and not tgisinternal),
  'functions',(select coalesce(jsonb_agg(to_jsonb(p) order by oid),'[]'::jsonb) from pg_proc p where oid in (to_regprocedure('private.guard_qualification_master_manager_company_move()'),to_regprocedure('private.guard_qualification_master_references()')))
)'''
out = r'''-- Review-only: generated with an independently captured installed catalog fingerprint.
begin;
set local search_path=''; set local lock_timeout='5s'; set local statement_timeout='45s';
lock table public.qualification_master,public.qualification_master_aliases,public.worker_qualifications,private.qualification_submissions,public.company_members in share row exclusive mode;
do $guard$ begin
  if current_user <> 'postgres' then raise exception 'wrong_operator'; end if;
  if md5((CATALOG)::text) <> 'EXPECTED' then raise exception 'installed_catalog_drift'; end if;
end $guard$;
drop trigger qualification_master_preserve_references on public.qualification_master;
drop trigger qualification_master_manager_company_immutable on public.qualification_master;
drop function private.guard_qualification_master_references();
drop function private.guard_qualification_master_manager_company_move();
drop policy "managers can update qualification master" on public.qualification_master;
drop policy "managers can delete qualification master" on public.qualification_master;
do $guard$ begin
  if md5(coalesce((select jsonb_agg(to_jsonb(p) order by policyname)::text from pg_policies p where schemaname='public' and tablename='qualification_master'),'[]')) <> '944941ef563914fa63b1c8edf99eb0f8' then raise exception 'original_policy_mismatch'; end if;
  if exists(select 1 from pg_trigger where tgrelid='public.qualification_master'::regclass and not tgisinternal) then raise exception 'unexpected_trigger'; end if;
end $guard$;
commit;
'''.replace('CATALOG', catalog).replace('EXPECTED', args.expected_installed_catalog_md5)
(Path(__file__).resolve().parent / 'root-restore.guarded.sql.review-only').write_text(out)
print('Review-only restore SQL prepared. No database operation performed.')
