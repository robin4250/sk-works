-- Approved fixed PNG designs; preserve every existing choice and document.
alter table public.companies drop constraint companies_company_seal_style_check;
alter table public.companies add constraint companies_company_seal_style_check
 check(company_seal_style in ('legacy','aoyagi_reisho','png_sumida_v1_standard','png_sumida_v1_light','png_sumida_v1_worn'));
alter table public.companies add constraint companies_company_seal_png_scope_check
 check(company_seal_style not in ('png_sumida_v1_standard','png_sumida_v1_light','png_sumida_v1_worn') or (id='0f117273-0a06-4a2f-85ec-720a3c9f4cf4'::uuid and name='すみだ建設株式会社'));

create or replace function public.company_seal_style_settings(p_company_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare uid uuid:=auth.uid(); result jsonb;
begin
 if uid is null or not private.account_access_allowed() or not exists(
  select 1 from public.company_members cm where cm.company_id=p_company_id
  and cm.user_id=uid and cm.role::text in ('owner','admin')) then
  raise exception 'owner or admin permission required' using errcode='42501';
 end if;
 select jsonb_build_object('company_id',c.id,'company_name',c.name,
  'company_seal_style',c.company_seal_style,'document_snapshot_version',1,
  'png_styles',case when c.id='0f117273-0a06-4a2f-85ec-720a3c9f4cf4'::uuid and c.name='すみだ建設株式会社'
  then jsonb_build_array('png_sumida_v1_standard','png_sumida_v1_light','png_sumida_v1_worn') else '[]'::jsonb end) into result
 from public.companies c where c.id=p_company_id;
 if result is null then raise exception 'company not found'; end if;
 return result;
end $$;

create or replace function public.save_company_seal_style(p_company_id uuid,p_style text,p_expected_name text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); current_name text;
begin
 if uid is null or not private.account_access_allowed() or not exists(
  select 1 from public.company_members cm where cm.company_id=p_company_id
  and cm.user_id=uid and cm.role::text in ('owner','admin')) then
  raise exception 'owner or admin permission required' using errcode='42501';
 end if;
 if p_style is null or p_style not in ('legacy','aoyagi_reisho','png_sumida_v1_standard','png_sumida_v1_light','png_sumida_v1_worn') then
  raise exception 'unsupported company seal style' using errcode='22023';
 end if;
 select c.name into current_name from public.companies c
 where c.id=p_company_id for update;
 if not found then raise exception 'company not found'; end if;
 -- Recheck authorization after any wait for the exact company row.
 if not private.account_access_allowed() or not exists(
  select 1 from public.company_members cm where cm.company_id=p_company_id
  and cm.user_id=uid and cm.role::text in ('owner','admin')) then
  raise exception 'owner or admin permission required' using errcode='42501';
 end if;
 if p_expected_name is distinct from current_name then
  raise exception 'company name changed: regenerate preview' using errcode='40001';
 end if;
 if p_style in ('png_sumida_v1_standard','png_sumida_v1_light','png_sumida_v1_worn') and (p_company_id is distinct from '0f117273-0a06-4a2f-85ec-720a3c9f4cf4'::uuid or current_name is distinct from 'すみだ建設株式会社') then
  raise exception 'PNG seal belongs to another company' using errcode='22023';
 end if;
 if p_style='aoyagi_reisho' and not private.aoyagi_reisho_name_supported(current_name) then
  raise exception 'unsupported or too small registered name for Reisho' using errcode='22023';
 end if;
 update public.companies c set company_seal_style=p_style,updated_at=now()
 where c.id=p_company_id;
 return public.company_seal_style_settings(p_company_id);
end $$;
revoke all on function public.company_seal_style_settings(uuid) from public,anon;
revoke all on function public.save_company_seal_style(uuid,text,text) from public,anon;
grant execute on function public.company_seal_style_settings(uuid) to authenticated;
grant execute on function public.save_company_seal_style(uuid,text,text) to authenticated;

-- Future documents only. No UPDATE/backfill of existing financial records.
create or replace function private.document_company_seal_snapshot(p_existing jsonb,p_company uuid,p_new boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.companies;
begin
 if not p_new then
  if coalesce(p_existing,'{}'::jsonb) ? 'company_seal_snapshot' then
   return jsonb_build_object('company_seal_snapshot',p_existing->'company_seal_snapshot');
  end if;
  return '{}'::jsonb;
 end if;
 select * into c from public.companies where id=p_company for share;
 if c.id is null then raise exception 'Company does not exist.' using errcode='23503'; end if;
 if c.name is null or btrim(c.name)='' then
  raise exception 'Registered company name is missing.' using errcode='22023';
 end if;
 if c.company_seal_style not in ('legacy','aoyagi_reisho','png_sumida_v1_standard','png_sumida_v1_light','png_sumida_v1_worn') then
  raise exception 'Unknown company seal style.' using errcode='22023';
 end if;
 if c.company_seal_style='aoyagi_reisho' and not private.aoyagi_reisho_name_supported(c.name) then
  raise exception 'Registered company name cannot be used for the selected seal.' using errcode='22023';
 end if;
 if c.company_seal_style in ('png_sumida_v1_standard','png_sumida_v1_light','png_sumida_v1_worn') then
  if c.id is distinct from '0f117273-0a06-4a2f-85ec-720a3c9f4cf4'::uuid or c.name is distinct from 'すみだ建設株式会社' then
   raise exception 'PNG seal belongs to another company' using errcode='22023';
  end if;
  return jsonb_build_object('company_seal_snapshot',jsonb_build_object(
   'version',1,'style',c.company_seal_style,'name',c.name,'company_id',c.id));
 end if;
 return jsonb_build_object('company_seal_snapshot',jsonb_build_object(
  'version',1,'style',c.company_seal_style,'name',c.name));
end $$;
revoke all on function private.document_company_seal_snapshot(jsonb,uuid,boolean) from public,anon,authenticated;
