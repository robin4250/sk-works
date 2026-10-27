#!/usr/bin/env python3
"""Generate review-only install / exact unused restore; never connects to a DB."""
import argparse
import hashlib
import pathlib
import re

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]

def sql(name):
    return (HERE / name).read_text().strip().rstrip(';')

CATALOG = sql('catalog-query.sql')
BUSINESS = sql('business-query.sql')
LOCKS = '''lock table public.worker_qualifications,public.workers,public.qualification_master,
 public.company_members,public.member_feature_permissions,private.worker_qualification_history,
 private.qualification_photo_history,private.qualification_submissions in share row exclusive mode;'''

def fingerprint_guard(catalog, business):
    return f"""do $guard$
declare catalog_value text; business_value text;
begin
 select catalog_md5 into catalog_value from ({CATALOG}) checked;
 select business_md5 into business_value from ({BUSINESS}) checked;
 if catalog_value is distinct from '{catalog}' or business_value is distinct from '{business}' then
  raise exception 'qualification management catalog/business drift' using errcode='55000';end if;
end $guard$;"""

def install(catalog, business):
    source = (ROOT / 'candidates/qualification_direct_management_20261027.sql.review-only').read_text()
    source, n = re.subn(r'(?m)^begin;\n', '', source, count=1)
    if n != 1 or not re.search(r'\ncommit;\s*\Z', source):
        raise ValueError('Expected single outer transaction in reviewed candidate')
    source = re.sub(r'\ncommit;\s*\Z', '', source)
    privacy = (ROOT / 'candidates/qualification_management_pending_privacy_20261027.sql.review-only').read_text()
    privacy,n = re.subn(r'(?m)^begin;\n', '', privacy, count=1)
    if n != 1 or not re.search(r'\ncommit;\s*\Z', privacy): raise ValueError('privacy transaction shape changed')
    source += '\n' + re.sub(r'\ncommit;\s*\Z', '', privacy)
    return f"""-- REVIEW ONLY. All original rows must remain unchanged. Initial state is OFF.
begin;
set local search_path='';
{LOCKS}
{fingerprint_guard(catalog,business)}
{source}
do $guard$ declare actual text;begin
 select business_md5 into actual from ({BUSINESS}) checked;
 if actual is distinct from '{business}' then raise exception 'qualification management changed original business data' using errcode='55000';end if;
 if (select enabled from private.qualification_management_state where singleton) is distinct from false
  or exists(select 1 from private.qualification_management_operations)
  or exists(select 1 from private.qualification_management_pending) then
  raise exception 'qualification management must install unused and OFF' using errcode='55000';end if;
end $guard$;
commit;
"""

def restore(installed_catalog, business, restored_catalog):
    return f"""-- REVIEW ONLY. Refuses any used audit, ON state or subsequent catalog/data change.
begin;
set local search_path='';
{LOCKS}
lock table private.qualification_management_state,private.qualification_management_operations,private.qualification_management_pending in access exclusive mode;
{fingerprint_guard(installed_catalog,business)}
do $guard$begin
 if (select enabled from private.qualification_management_state where singleton) is distinct from false
  or exists(select 1 from private.qualification_management_operations)
  or exists(select 1 from private.qualification_management_pending) then
  raise exception 'used qualification management must be held OFF; never erase audit' using errcode='55000';end if;
end $guard$;
do $cron_guard$declare job_id bigint;job_command text;job_schedule text;
begin
 if to_regclass('cron.job') is not null then
  execute 'lock table cron.job in share row exclusive mode';
  execute 'select jobid,command,schedule from cron.job where jobname=''sko-qualification-command-expiry''' into job_id,job_command,job_schedule;
  if job_id is not null then
   if job_command is distinct from 'select private.purge_qualification_management_pending();' or job_schedule is distinct from '* * * * *' then
    raise exception 'scheduled cleanup drift; review required' using errcode='55000';end if;
   execute 'select cron.unschedule($1)' using 'sko-qualification-command-expiry';
  end if;
 end if;
end $cron_guard$;
drop policy qualification_management_update_role_boundary on public.worker_qualifications;
drop policy qualification_management_delete_role_boundary on public.worker_qualifications;
drop function public.qualification_direct_management(text,jsonb);
drop function private.qualification_direct_management(text,jsonb);
drop function private.qualification_direct_management_writer(text,jsonb);
drop function private.qualification_management_pending_result(private.qualification_management_pending);
drop function private.qualification_management_cleanup_healthy();
drop function private.purge_qualification_management_pending();
drop table private.qualification_management_pending;
drop function private.qualification_management_result(private.qualification_management_operations);
drop function private.qualification_manager_can_write(uuid);
drop table private.qualification_management_operations;
drop table private.qualification_management_state;
drop function private.qualification_management_audit_immutable();
{fingerprint_guard(restored_catalog,business)}
commit;
"""

if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--before-catalog-md5', required=True)
    p.add_argument('--business-md5', required=True)
    p.add_argument('--installed-catalog-md5')
    p.add_argument('--output-dir', type=pathlib.Path, default=HERE)
    args = p.parse_args()
    for value in (args.before_catalog_md5,args.business_md5,args.installed_catalog_md5):
        if value is not None and re.fullmatch('[0-9a-f]{32}', value) is None:
            raise ValueError('Exact MD5 fingerprint required')
    args.output_dir.mkdir(parents=True,exist_ok=True)
    files={'install-off.guarded.sql.review-only':install(args.before_catalog_md5,args.business_md5)}
    if args.installed_catalog_md5:
        files['restore-unused.guarded.sql.review-only']=restore(args.installed_catalog_md5,args.business_md5,args.before_catalog_md5)
    for name, body in files.items():
        (args.output_dir/name).write_text(body)
        print(name,hashlib.sha256(body.encode()).hexdigest())
