create table private.worker_qualification_history(id uuid primary key default gen_random_uuid(),company_id uuid not null,worker_id uuid not null,source_id uuid not null,attachment_path text,snapshot jsonb not null,operation text not null,changed_by uuid,changed_at timestamptz not null default clock_timestamp());
alter table private.worker_qualification_history enable row level security;
revoke all on private.worker_qualification_history from public,anon,authenticated;
CREATE OR REPLACE FUNCTION private.capture_official_qualification_history()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if tg_op='UPDATE' and to_jsonb(old)=to_jsonb(new) then return new; end if;
 -- Capture OLD as well: documents predating this migration have no baseline.
 if tg_op in ('UPDATE','DELETE') then
  insert into private.worker_qualification_history(company_id,worker_id,source_id,attachment_path,snapshot,operation,changed_by)
  values(old.company_id,old.worker_id,old.id,old.attachment_path,to_jsonb(old),case when tg_op='DELETE' then 'delete' else 'before_update' end,auth.uid());
 end if;
 if tg_op<>'DELETE' then
  insert into private.worker_qualification_history(company_id,worker_id,source_id,attachment_path,snapshot,operation,changed_by)
  values(new.company_id,new.worker_id,new.id,new.attachment_path,to_jsonb(new),lower(tg_op),auth.uid());
  return new;
 end if;
 return old;
end $function$;

create trigger capture_official_qualification_history after insert or update or delete on public.worker_qualifications for each row execute function private.capture_official_qualification_history();
