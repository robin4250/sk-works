"""Build review-only forward/unused restore from checked original definitions."""
import hashlib,json,pathlib
root=pathlib.Path(__file__).resolve().parents[3]
folder=pathlib.Path(__file__).resolve().parent
rows=json.loads((folder/'baseline-catalog.json').read_text())
by={r['signature']:r for r in rows}
modified={}
sig='private.reauthentication_scope(text)'
old=by[sig]['definition'];needle="  when 'master.security_collector.read' then 'master_security' end"
assert old.count(needle)==1
modified[sig]=old.replace(needle,"  when 'master.security_collector.read' then 'master_security'\n  when 'employee.bank.initial' then 'employee_bank_registration' end")
sig='private.reauthentication_required(text)';old=by[sig]['definition'];needle='begin\n select enabled into required'
assert old.count(needle)==1
modified[sig]=old.replace(needle,"begin\n if p_scope='employee_bank_registration' then return private.employee_bank_initial_enabled();end if;\n select enabled into required")
sig='public.issue_reauthentication_proof(uuid,uuid,text,jsonb,text)';old=by[sig]['definition'];needle="AS $function$begin\n"
assert old.count(needle)==1
new=old.replace(needle,"AS $function$declare expiry timestamptz;\nbegin\n")
needle=' return private.issue_reauthentication_proof(p_actor,p_session,p_operation,p_target,p_proof_hash);'
assert new.count(needle)==1
modified[sig]=new.replace(needle,""" -- Shared issuer establishes genuine actor/live original SID and one ledger
 -- entry first. A later bank target/permission failure rolls back that entry.
 expiry:=private.issue_reauthentication_proof(p_actor,p_session,p_operation,p_target,p_proof_hash);
 if p_operation='employee.bank.initial' then perform private.employee_bank_initial_issue_target(p_actor,p_target);end if;
 return expiry;""")
sig='private.sync_bank_document_status()';old=by[sig]['definition']
needle='  if auth.uid() is null or not exists ('
assert old.count(needle)==1
new=old.replace(needle,'  if auth.uid() is null or (not exists (')
needle="  ) then raise exception 'own bank account required'; end if;"
assert new.count(needle)==1
replacement="""  ) and not (tg_op='INSERT' and private.has_company_feature(new.company_id,'can_manage_payroll') and exists(
    select 1 from private.employee_bank_initial_context c
    join private.reauthentication_proofs p on p.proof_hash=c.proof_hash
    where c.transaction_id=pg_current_xact_id() and c.actor_id=auth.uid()
      and c.session_id=private.require_reauthentication_session()
      and c.company_id=new.company_id and c.worker_id=new.worker_id
      and c.input_sha256=private.employee_bank_initial_digest(new.company_id,new.worker_id,jsonb_build_object(
        'bank_name',new.bank_name,'branch_name',new.branch_name,'account_type',new.account_type,
        'account_number',new.account_number,'account_holder',new.account_holder))
      and p.actor_id=c.actor_id and p.session_id=c.session_id and p.operation='employee.bank.initial'
      and p.target=jsonb_build_object('company_id',c.company_id,'worker_id',c.worker_id,'input_sha256',c.input_sha256)
      and p.consumed_at is not null and p.expires_at>clock_timestamp()
  ))) then raise exception 'own bank account required'; end if;"""
modified[sig]=new.replace(needle,replacement)

def guard(expected):
 vals=',\n'.join(" ('%s','%s')"%(sig,digest) for sig,digest in expected.items())
 return """do $guard$ declare item record;begin
 for item in select * from (values
%s
 ) v(signature,definition_hash) loop
  if to_regprocedure(item.signature) is null or md5(pg_get_functiondef(to_regprocedure(item.signature)))<>item.definition_hash then
   raise sqlstate '55000' using message='employee_bank_original_definition_changed';end if;
 end loop;
end $guard$;
"""%vals
header="-- REVIEW ONLY. No production apply/GRANT/activation authorization. Default OFF.\n-- Exact original-definition guard: inspect/review again if any prerequisite drifts.\nbegin;\n"
forward=header+guard({r['signature']:r['md5'] for r in rows})
forward+="""do $$begin
 if to_regclass('private.employee_bank_initial_context') is not null
  or to_regprocedure('private.employee_bank_initial_enabled()') is not null then
  raise sqlstate '55000' using message='employee_bank_candidate_already_present';end if;
end $$;
"""
forward+=(folder/'candidate-helpers.sql').read_text()+'\n'
forward+='\n'.join(v+';' for v in modified.values())+'\ncommit;\n'
(root/'tool/staged/employee_bank_initial_registration.sql.review-only').write_text(forward)
# pg_get_functiondef normalization for CREATE FUNCTION bodies is checked by the
# native fixture before this unused restore is accepted as ready.
restore=header+guard({sig:hashlib.md5(definition.encode()).hexdigest() for sig,definition in modified.items()})
restore+="""do $$begin
 if private.employee_bank_initial_enabled() or exists(select 1 from private.employee_bank_initial_context)
  or exists(select 1 from private.reauthentication_proofs where operation='employee.bank.initial') then
  raise sqlstate '55000' using message='employee_bank_unused_restore_requires_off_empty_context_and_no_bank_proofs';end if;
end $$;
"""
restore+='\n'.join(by[sig]['definition']+';' for sig in modified)+'\n'
restore+='''drop function public.register_employee_bank_initial(uuid,uuid,jsonb,text);
drop function public.employee_bank_initial_capability(uuid,uuid);
drop function private.employee_bank_initial_issue_target(uuid,jsonb);
drop function private.employee_bank_initial_scope(uuid,uuid,uuid);
drop function private.employee_bank_initial_digest(uuid,uuid,jsonb);
drop table private.employee_bank_initial_context;
drop function private.employee_bank_initial_enabled();
-- Bank rows, original statuses/attachments, proof history and payroll are retained.
commit;
'''
(root/'tool/staged/employee_bank_initial_registration.restore-unused.sql.review-only').write_text(restore)
(folder/'expected-candidate-definitions.json').write_text(json.dumps(modified,ensure_ascii=False,indent=2)+'\n')
