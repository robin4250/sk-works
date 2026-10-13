-- Paid leave request workflow.
-- Builds on the paid leave foundation without mutating attendance yet.

create or replace function public.submit_paid_leave_request(
  p_company_id uuid,
  p_person_id uuid,
  p_leave_date date,
  p_days numeric default 1,
  p_note text default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request_id uuid;
  v_remaining numeric;
begin
  if p_days <= 0 then
    raise exception 'paid leave days must be positive';
  end if;

  select granted_days - used_days
    into v_remaining
    from public.paid_leave_balances
   where company_id = p_company_id
     and person_id = p_person_id
   for update;

  if v_remaining is null then
    raise exception 'paid leave balance not found';
  end if;

  if p_days > v_remaining then
    raise exception 'paid leave balance exceeded';
  end if;

  insert into public.paid_leave_requests (
    company_id, person_id, leave_date, days, note, status
  ) values (
    p_company_id, p_person_id, p_leave_date, p_days, p_note, 'pending'
  ) returning id into v_request_id;

  return v_request_id;
end;
$$;

create or replace function public.approve_paid_leave_request(
  p_request_id uuid,
  p_approver_id uuid
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.paid_leave_requests%rowtype;
  v_remaining numeric;
begin
  select * into v_request
    from public.paid_leave_requests
   where id = p_request_id
   for update;

  if v_request.id is null then
    raise exception 'paid leave request not found';
  end if;

  if v_request.status <> 'pending' then
    raise exception 'paid leave request is not pending';
  end if;

  select granted_days - used_days
    into v_remaining
    from public.paid_leave_balances
   where company_id = v_request.company_id
     and person_id = v_request.person_id
   for update;

  if v_remaining is null or v_request.days > v_remaining then
    raise exception 'paid leave balance exceeded';
  end if;

  update public.paid_leave_balances
     set used_days = used_days + v_request.days,
         updated_at = now()
   where company_id = v_request.company_id
     and person_id = v_request.person_id;

  update public.paid_leave_requests
     set status = 'approved',
         approved_by = p_approver_id,
         approved_at = now(),
         updated_at = now()
   where id = p_request_id;
end;
$$;
