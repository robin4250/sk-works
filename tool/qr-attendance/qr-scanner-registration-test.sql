\set ON_ERROR_STOP on
-- Synthetic Auth, permission and exact-proof fixture. Candidate registration SQL
-- is real. This does not test the existing proof issuer, which does not support
-- qr.scanner.register and therefore cannot activate this path.
do $$begin if not exists(select from pg_roles where rolname='service_role') then create role service_role;end if;end$$;
\ir qr-scanner-context-test.sql
insert into auth.sessions values('00000000-0000-4000-8000-000000000006','00000000-0000-4000-8000-000000000005');
create table private.registration_test_proofs(proof text primary key,actor uuid,session_id uuid,operation text,target jsonb,consumed boolean default false);
create function private.consume_reauthentication_proof(p_operation text,p_target jsonb,p_proof text) returns void language plpgsql as $$
declare n integer;begin
 update private.registration_test_proofs set consumed=true where proof=p_proof and actor=auth.uid()
 and session_id=private.require_reauthentication_session() and operation=p_operation and target=p_target and not consumed;
 get diagnostics n=row_count;
 if n<>1 then raise sqlstate '42501' using message='test_exact_proof_denied';end if;
end$$;
\ir qr-scanner-registration.sql.review-only
create function private.registration_test_proof(p_proof text,p_device uuid default '00000000-0000-4000-8000-000000000020') returns void language sql as $$
 insert into private.registration_test_proofs(proof,actor,session_id,operation,target) values(p_proof,auth.uid(),private.require_reauthentication_session(),'qr.scanner.register',jsonb_build_object(
 'company_id','00000000-0000-4000-8000-000000000001'::uuid,'device_id',p_device,'actor_id',auth.uid(),
 'public_key_hex','302a300506032b6570032100'||repeat('ab',32)))
$$;
create function private.registration_test_call(p_proof text,p_key text default '302a300506032b6570032100'||repeat('ab',32),p_company uuid default '00000000-0000-4000-8000-000000000001') returns uuid language sql as $$
 select qr_attendance_private.register_own_scanner_with_proof(p_company,'00000000-0000-4000-8000-000000000020',p_key,p_proof)
$$;
select private.registration_test_proof('first');
do $$begin
 begin perform private.registration_test_call('missing');raise exception 'missing proof accepted';exception when insufficient_privilege then null;end;
 begin perform private.registration_test_call('first',repeat('ab',44));raise exception 'noncanonical key accepted';exception when insufficient_privilege then null;end;
 begin perform private.registration_test_call('first',p_company=>'00000000-0000-4000-8000-000000000099');raise exception 'foreign company accepted';exception when insufficient_privilege then null;end;
 perform set_config('fixture.manage','no',false);
 begin perform private.registration_test_call('first');raise exception 'unprivileged registration';exception when insufficient_privilege then null;end;
 perform set_config('fixture.manage','yes',false);perform set_config('fixture.live','no',false);
 begin perform private.registration_test_call('first');raise exception 'expired registration';exception when insufficient_privilege then null;end;
 perform set_config('fixture.live','yes',false);
 if exists(select 1 from private.registration_test_proofs where proof='first' and consumed) then raise exception 'failed check consumed proof';end if;
 perform private.registration_test_call('first');
 if (select count(*) from qr_attendance_private.scanner_registration_events)<>1 then raise exception 'audit missing';end if;
 begin perform private.registration_test_call('first');raise exception 'replay accepted';exception when insufficient_privilege then null;end;
end$$;
select private.registration_test_proof('confirm');
select private.registration_test_call('confirm');
select private.registration_test_proof('replace');
do $$begin
 begin perform private.registration_test_call('replace','302a300506032b6570032100'||repeat('cd',32));raise exception 'key replaced';exception when insufficient_privilege then null;end;
 if exists(select 1 from private.registration_test_proofs where proof='replace' and consumed) then raise exception 'replacement consumed proof';end if;
 update qr_attendance_private.registered_scanners set revoked_at=clock_timestamp() where device_id='00000000-0000-4000-8000-000000000020';
 begin perform private.registration_test_call('replace');raise exception 'revoked reactivated';exception when insufficient_privilege then null;end;
 update qr_attendance_private.registered_scanners set revoked_at=null where device_id='00000000-0000-4000-8000-000000000020';
 if (select count(*) from qr_attendance_private.registered_scanners where device_id='00000000-0000-4000-8000-000000000020')<>1 or
 (select count(*) from qr_attendance_private.scanner_registration_events)<>2 then raise exception 'duplicate registry or audit';end if;
end$$;
-- A post-consumption failure must undo proof consumption as well as registry.
create function private.registration_test_reject_audit() returns trigger language plpgsql as $$begin raise sqlstate '42501' using message='test_audit_failure';end$$;
create trigger reject_test_audit before insert on qr_attendance_private.scanner_registration_events for each row execute function private.registration_test_reject_audit();
select private.registration_test_proof('audit-failure');
select private.registration_test_proof('audit-failure-new','00000000-0000-4000-8000-000000000021');
do $$begin
 begin perform private.registration_test_call('audit-failure');raise exception 'audit failure ignored';exception when insufficient_privilege then null;end;
 if exists(select 1 from private.registration_test_proofs where proof='audit-failure' and consumed) then raise exception 'audit failure consumed proof';end if;
 begin
  perform qr_attendance_private.register_own_scanner_with_proof('00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000021','302a300506032b6570032100'||repeat('ab',32),'audit-failure-new');
  raise exception 'new registration audit failure ignored';
 exception when insufficient_privilege then null;end;
 if exists(select 1 from qr_attendance_private.registered_scanners where device_id='00000000-0000-4000-8000-000000000021')
 or exists(select 1 from private.registration_test_proofs where proof='audit-failure-new' and consumed) then raise exception 'new registration did not rollback';end if;
 if has_function_privilege('authenticated','qr_attendance_private.register_own_scanner_with_proof(uuid,uuid,text,text)','execute') or
 has_function_privilege('service_role','qr_attendance_private.register_own_scanner_with_proof(uuid,uuid,text,text)','execute') or
 has_table_privilege('authenticated','qr_attendance_private.scanner_registration_events','select') then raise exception 'registration exposed';end if;
end$$;
