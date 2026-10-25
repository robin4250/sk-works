from pathlib import Path
import json,re,hashlib
p=Path(__file__).parent
pins=json.loads((p/'source-pins.json').read_text())
s=(p/'management-registered-allowances.sql.review-only').read_text()
def digest(name):
 start=s.index('CREATE OR REPLACE FUNCTION '+name+'(')
 part=s[start:];m=re.search(r'AS (\$\w*\$)(.*?)\1',part,re.S);assert m
 return hashlib.md5(m[2].encode()).hexdigest()
out=['-- REVIEW ONLY: default-OFF, unused rollback. No business rows are deleted.\nbegin;\nlock table management_registered_allowance_private.rollout in access exclusive mode;\ndo $guard$ begin\n']
for row,name in zip(pins,['public.force_manage_attendance','attendance_admin_override_private.permit_roster']):
 sig=('public.'+row['signature']) if '.' not in row['signature'].split('(')[0] else row['signature']
 out.append(f" if not exists(select 1 from pg_proc where oid=to_regprocedure('{sig}') and md5(prosrc)='{digest(name)}' and pg_get_userbyid(proowner)='postgres' and prosecdef) then raise exception 'management_allowance_restore_source_mismatch';end if;\n")
out.append(""" if exists(select 1 from management_registered_allowance_private.rollout) then raise exception 'management_allowance_restore_requires_never_enabled';end if;
 if exists(select 1 from company_checkout_allowance_private.receipts where snapshot#>>'{authority,kind}'='attendance_management') then raise exception 'management_allowance_restore_has_receipts';end if;
 if exists(select 1 from attendance_admin_override_private.operations o,lateral jsonb_array_elements(o.items) x where x?'company_allowance_selections' or x?'company_allowance_legacy_labels') then raise exception 'management_allowance_restore_has_typed_operations';end if;
end $guard$;
""")
for row in pins:
 sig=('public.'+row['signature']) if '.' not in row['signature'].split('(')[0] else row['signature']
 out.append(row['definition'].rstrip().rstrip(';')+';\n')
 out.append(f'alter function {sig} owner to postgres;\nrevoke all on function {sig} from public,anon,authenticated,service_role;\n')
 if row['signature'].startswith('force_manage'):out.append(f'grant execute on function {sig} to authenticated,service_role;\n')
out.append('''drop function public.read_management_company_allowance_options(uuid[]);
drop function management_registered_allowance_private.matches(uuid,uuid,jsonb,jsonb);
drop function management_registered_allowance_private.capture(uuid,uuid,jsonb);
drop function management_registered_allowance_private.plan(uuid,uuid,date,uuid,jsonb);
drop function management_registered_allowance_private.check_payload(uuid,text,jsonb);
drop function management_registered_allowance_private.enabled(uuid);
drop table management_registered_allowance_private.rollout;
drop schema management_registered_allowance_private;
commit;
''')
(p/'management-registered-allowances.unused-restore.sql.review-only').write_text(''.join(out))
