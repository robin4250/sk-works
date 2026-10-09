-- Additive, staged OFF. Existing profiles, approval RPCs and RLS stay unchanged.
create table private.invoice_stamp_surname_rollout (
 company_id uuid primary key references public.companies(id) on delete cascade,
 enabled boolean not null default false
);
create table private.invoice_stamp_surname_drafts (
 invoice_id uuid not null references public.invoices(id) on delete cascade,
 approver_user_id uuid not null,
 surname text not null check(length(surname) between 1 and 30),
 primary key(invoice_id,approver_user_id)
);
create table private.invoice_stamp_surname_snapshots (
 invoice_id uuid not null references public.invoices(id) on delete cascade,
 approver_user_id uuid not null,
 approved_at timestamptz not null,
 surname text not null check(length(surname) between 1 and 30),
 primary key(invoice_id,approver_user_id,approved_at)
);
create table private.invoice_stamp_surname_history (
 event_id uuid primary key default gen_random_uuid(),
 invoice_id uuid not null references public.invoices(id) on delete cascade,
 approver_user_id uuid not null,
 surname text not null,
 recorded_at timestamptz not null default clock_timestamp()
);
alter table private.invoice_stamp_surname_rollout enable row level security;
alter table private.invoice_stamp_surname_drafts enable row level security;
alter table private.invoice_stamp_surname_snapshots enable row level security;
alter table private.invoice_stamp_surname_history enable row level security;
revoke all on private.invoice_stamp_surname_rollout,private.invoice_stamp_surname_drafts,
 private.invoice_stamp_surname_snapshots,private.invoice_stamp_surname_history from public,anon,authenticated;

create function public.invoice_stamp_surname_rows(p_invoice_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare cid uuid; enabled boolean; result jsonb;
begin
 -- The existing v2 RPC validates this exact invoice/company and approval rows.
 perform 1 from public.invoice_approval_status_rows_v2(p_invoice_id);
 select i.company_id into cid from public.invoices i where i.id=p_invoice_id;
 select coalesce(r.enabled,false) into enabled from private.invoice_stamp_surname_rollout r where r.company_id=cid;
 select coalesce(jsonb_agg(jsonb_build_object(
 'user_id',a.approver_user_id,'snapshot_surname',s.surname,
 'draft_surname',case when a.approver_user_id=auth.uid() and a.status='pending' then d.surname else null end,
 'can_set_surname',coalesce(enabled,false) and a.approver_user_id=auth.uid() and a.status='pending') order by a.position),'[]'::jsonb)
 into result from public.invoice_approval_status_rows_v2(p_invoice_id) a
 left join private.invoice_stamp_surname_snapshots s on s.invoice_id=p_invoice_id
 and s.approver_user_id=a.approver_user_id and s.approved_at=a.approved_at and a.status='approved'
 left join private.invoice_stamp_surname_drafts d on d.invoice_id=p_invoice_id and d.approver_user_id=a.approver_user_id;
 return jsonb_build_object('enabled',coalesce(enabled,false),'names',result);
end $$;

create function public.set_invoice_stamp_surname(p_invoice_id uuid,p_surname text)
returns void language plpgsql security definer set search_path='' as $$
declare cid uuid; value text:=btrim(p_surname);
begin
 perform 1 from public.invoice_approval_status_rows_v2(p_invoice_id);
 select i.company_id into cid from public.invoices i where i.id=p_invoice_id;
 perform 1 from public.companies c where c.id=cid for update;
 perform 1 from public.invoices i where i.id=p_invoice_id and i.company_id=cid for update;
 if not found then raise exception 'invoice not found' using errcode='42501'; end if;
 perform 1 from public.invoice_approval_status_rows_v2(p_invoice_id);
 perform 1 from private.invoice_stamp_surname_rollout r where r.company_id=cid and r.enabled for share;
 if not found then raise exception 'surname setting unavailable' using errcode='55000'; end if;
 if not exists(select 1 from public.invoice_approvals a where a.invoice_id=p_invoice_id
 and a.company_id=cid and a.approver_user_id=auth.uid() and a.status='pending') then
 raise exception 'pending own approval required' using errcode='42501'; end if;
 if value is null or length(value) not between 1 and 30 or value ~ '[[:cntrl:]]' then
 raise exception 'explicit surname required (1 to 30 characters)' using errcode='22023'; end if;
 insert into private.invoice_stamp_surname_drafts(invoice_id,approver_user_id,surname)
 values(p_invoice_id,auth.uid(),value) on conflict(invoice_id,approver_user_id) do update set surname=excluded.surname;
 insert into private.invoice_stamp_surname_history(invoice_id,approver_user_id,surname)
 values(p_invoice_id,auth.uid(),value);
end $$;

create function public.approve_invoice_with_stamp_surname(p_invoice_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare cid uuid; value text; actual timestamptz; was_pending boolean; final boolean;
begin
 perform 1 from public.invoice_approval_status_rows_v2(p_invoice_id);
 select i.company_id into cid from public.invoices i where i.id=p_invoice_id;
 perform 1 from public.companies c where c.id=cid for update;
 perform 1 from public.invoices i where i.id=p_invoice_id and i.company_id=cid for update;
 if not found then raise exception 'invoice not found' using errcode='42501'; end if;
 perform 1 from public.invoice_approval_status_rows_v2(p_invoice_id);
 perform 1 from private.invoice_stamp_surname_rollout r where r.company_id=cid and r.enabled for share;
 if not found then raise exception 'surname setting unavailable' using errcode='55000'; end if;
 select a.status='pending' into was_pending from public.invoice_approvals a
 where a.invoice_id=p_invoice_id and a.company_id=cid and a.approver_user_id=auth.uid();
 if was_pending is null then raise exception 'own approval required' using errcode='42501'; end if;
 select d.surname into value from private.invoice_stamp_surname_drafts d
 where d.invoice_id=p_invoice_id and d.approver_user_id=auth.uid();
 if was_pending and value is null then raise exception 'set explicit surname before approval' using errcode='22023'; end if;
 final:=public.approve_invoice(p_invoice_id);
 if was_pending then
  select a.approved_at into actual from public.invoice_approvals a where a.invoice_id=p_invoice_id
  and a.approver_user_id=auth.uid() and a.status='approved';
  if actual is null then raise exception 'approval timestamp unavailable'; end if;
  insert into private.invoice_stamp_surname_snapshots(invoice_id,approver_user_id,approved_at,surname)
  values(p_invoice_id,auth.uid(),actual,value);
 end if;
 return final;
end $$;
revoke all on function public.invoice_stamp_surname_rows(uuid),
 public.set_invoice_stamp_surname(uuid,text),public.approve_invoice_with_stamp_surname(uuid) from public,anon;
grant execute on function public.invoice_stamp_surname_rows(uuid),
 public.set_invoice_stamp_surname(uuid,text),public.approve_invoice_with_stamp_surname(uuid) to authenticated;
