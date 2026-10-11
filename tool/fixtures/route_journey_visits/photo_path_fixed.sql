set role authenticated;
insert into storage.objects(bucket_id,name) values('attendance-evidence','31000000-0000-0000-0000-000000000001/attendance/route/31000000-0000-0000-0000-000000000003/fixed.jpg');
do $$declare p text; begin
 foreach p in array array[
  '31000000-0000-0000-0000-000000000001/attendance/route/31000000-0000-0000-0000-000000000004/foreign.jpg',
  '31000000-0000-0000-0000-000000000009/attendance/route/31000000-0000-0000-0000-000000000003/company.jpg',
  'bad/path'
 ] loop
  begin
   insert into storage.objects(bucket_id,name) values('attendance-evidence',p);
   raise exception 'non-owner/malformed upload was allowed';
  exception when insufficient_privilege then null; end;
 end loop;
end$$;
reset role;
