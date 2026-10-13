select set_config('test.actor','31000000-0000-0000-0000-000000000002',false);
select set_config('test.blocked','false',false);
insert into workers(id,company_id,status,user_id,name) values
 ('31000000-0000-0000-0000-000000000003','31000000-0000-0000-0000-000000000001','active','31000000-0000-0000-0000-000000000002','日本語の氏名'),
 ('31000000-0000-0000-0000-000000000004','31000000-0000-0000-0000-000000000001','active','31000000-0000-0000-0000-000000000005','別の従業員');
set role authenticated;
do $$begin
 begin
  insert into storage.objects(bucket_id,name) values('attendance-evidence','31000000-0000-0000-0000-000000000001/attendance/route/31000000-0000-0000-0000-000000000003/original.jpg');
  raise exception 'expected original policy to reject valid owner photo';
 exception when insufficient_privilege then null; end;
end$$;
reset role;
