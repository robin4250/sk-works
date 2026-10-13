create or replace function public.save_daily_report_reporter_signature(
  p_report_id uuid,
  p_signer_name text,
  p_signature_json jsonb
)
returns void
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
declare
  v_user uuid:=auth.uid();
  v_company uuid;
  v_status text;
begin
  if v_user is null then raise exception 'authentication required'; end if;
  if nullif(trim(coalesce(p_signer_name,'')),'') is null then
    raise exception 'signer name is required';
  end if;
  if p_signature_json is null or p_signature_json='[]'::jsonb then
    raise exception 'signature is required';
  end if;

  select dr.company_id,dr.status
    into v_company,v_status
  from public.daily_reports dr
  join public.company_members cm
    on cm.company_id=dr.company_id
   and cm.user_id=v_user
  where dr.id=p_report_id
  for update;

  if v_company is null then raise exception 'daily report not found'; end if;
  if v_status='signed' then
    raise exception 'signed report requires edit approval';
  end if;

  update public.daily_reports
  set representative_signer_name=trim(p_signer_name),
      representative_signature_json=p_signature_json,
      updated_by=v_user,
      updated_at=now()
  where id=p_report_id;
end;
$$;

revoke all on function public.save_daily_report_reporter_signature(uuid,text,jsonb) from public;
grant execute on function public.save_daily_report_reporter_signature(uuid,text,jsonb) to authenticated;
