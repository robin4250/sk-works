\set ON_ERROR_STOP on
create role authenticated nologin;
create schema private;
create table public.qualification_master(id integer primary key);
create table public.worker_qualifications(id integer primary key,qualification_master_id integer references public.qualification_master(id) on delete restrict);
create table public.qualification_master_aliases(id integer primary key,qualification_master_id integer references public.qualification_master(id) on delete cascade);
create table private.qualification_submissions(id integer primary key,qualification_master_id integer references public.qualification_master(id));
\i docs/review/qualification-master-access/delete-preserve.sql.review-only
insert into public.qualification_master values (1),(2),(3),(4);
insert into public.worker_qualifications values (1,1);
insert into public.qualification_master_aliases values (2,2);
insert into private.qualification_submissions values (3,3);
grant select,delete on public.qualification_master to authenticated;
set role authenticated;
do $$ declare n int; i int; begin
  for i in 1..3 loop
    begin delete from public.qualification_master where id=i;
      raise exception 'referenced record % unexpectedly deleted',i;
    exception when foreign_key_violation then null; end;
  end loop;
  delete from public.qualification_master where id=4;
  get diagnostics n=row_count; assert n=1,'unused record not deleted';
end $$;
reset role;
do $$ begin
  assert (select count(*)=1 from public.worker_qualifications);
  assert (select count(*)=1 from public.qualification_master_aliases);
  assert (select count(*)=1 from private.qualification_submissions);
  assert not has_function_privilege('authenticated','private.guard_qualification_master_references()','execute');
end $$;
