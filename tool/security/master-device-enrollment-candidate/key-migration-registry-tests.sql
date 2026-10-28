begin;
insert into private.master_devices(id,master_user_id,device_key,device_name,device_type,is_locked)
 values ('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000002','pending-fixture-only','fixture','iphone',false);
insert into master_device_enrollment_candidate.pending_key_migrations(actor,device_id,public_key_pem,key_sha256)
 values ('10000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001',repeat('x',178),repeat('a',64));
do $$ begin
 if exists(select 1 from master_device_enrollment_candidate.pending_key_migrations where status<>'pending') then raise exception 'trusted row created'; end if;
 begin
 insert into master_device_enrollment_candidate.pending_key_migrations(actor,device_id,public_key_pem,key_sha256,status)
 values ('10000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001',repeat('x',178),repeat('b',64),'active');
 raise exception 'active accepted'; exception when check_violation then null; end;
 begin
 insert into master_device_enrollment_candidate.pending_key_migrations(actor,device_id,public_key_pem,key_sha256)
 values ('10000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001',repeat('x',178),repeat('b',64));
 raise exception 'foreign accepted'; exception when insufficient_privilege then null; end;
 if has_table_privilege('authenticated','master_device_enrollment_candidate.pending_key_migrations','INSERT') or
 has_table_privilege('anon','master_device_enrollment_candidate.pending_key_migrations','SELECT') then raise exception 'client grant'; end if;
end $$;
rollback;
