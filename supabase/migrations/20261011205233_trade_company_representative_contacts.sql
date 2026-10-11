begin;
set local lock_timeout='5s';
alter table public.trade_companies
 add column representative_name text not null default '',
 add column representative_phone text not null default '',
 add constraint trade_company_representative_name_length check(char_length(representative_name)<=200),
 add constraint trade_company_representative_phone_length check(char_length(representative_phone)<=60);
-- Delegate every pre-existing company write, role check and legacy link to the
-- current implementation. Contract settings and their payroll linkage stay intact.
create function private.save_trade_company_contact(p_data jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare cid uuid; rid uuid; v_representative text; v_phone text;
begin
 cid:=private.current_company_admin_id();
 if auth.uid() is null or cid is null or not private.account_access_allowed() then
 raise exception '会社情報を変更する権限がありません' using errcode='42501'; end if;
 v_representative:=btrim(coalesce(p_data->>'representative_name',''));
 v_phone:=btrim(coalesce(p_data->>'representative_phone',''));
 if char_length(v_representative)>200 or char_length(v_phone)>60 then
 raise exception '代表者氏名または電話番号が長すぎます' using errcode='22023'; end if;
 rid:=private.save_trade_company(nullif(p_data->>'id','')::uuid,p_data->>'name',p_data->>'trade_role',
 p_data->>'postal_code',p_data->>'address',p_data->>'phone',p_data->>'email',
 p_data->>'corporate_number',p_data->>'notes');
 update public.trade_companies set representative_name=v_representative,representative_phone=v_phone
 where id=rid and company_id=cid;
 if not found then raise exception '会社情報の保存結果を確認できません' using errcode='42501'; end if;
 return rid;
end $$;
revoke all on function private.save_trade_company_contact(jsonb) from public,anon;
grant execute on function private.save_trade_company_contact(jsonb) to authenticated;
create function public.save_trade_company_contact(p_data jsonb)
returns uuid language sql security invoker set search_path='' as $$
 select private.save_trade_company_contact(p_data);
$$;
revoke all on function public.save_trade_company_contact(jsonb) from public,anon;
grant execute on function public.save_trade_company_contact(jsonb) to authenticated;
create function private.trade_company_contact_workspace()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare cid uuid; existing jsonb;
begin
 cid:=private.current_company_admin_id();
 if auth.uid() is null or cid is null or not private.account_access_allowed() then
 raise exception '会社情報の閲覧権限がありません' using errcode='42501'; end if;
 existing:=private.trade_company_workspace();
 return coalesce((select jsonb_agg(x.value||jsonb_build_object(
 'representative_name',t.representative_name,'representative_phone',t.representative_phone) order by x.position)
 from jsonb_array_elements(existing) with ordinality x(value,position)
 join public.trade_companies t on t.id=(x.value->>'id')::uuid and t.company_id=cid),'[]'::jsonb);
end $$;
revoke all on function private.trade_company_contact_workspace() from public,anon;
grant execute on function private.trade_company_contact_workspace() to authenticated;
create function public.trade_company_contact_workspace()
returns jsonb language sql stable security invoker set search_path='' as $$
 select private.trade_company_contact_workspace();
$$;
revoke all on function public.trade_company_contact_workspace() from public,anon;
grant execute on function public.trade_company_contact_workspace() to authenticated;
commit;
