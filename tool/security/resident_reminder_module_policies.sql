-- Exact non-personal policy definitions read from the reviewed production catalog.
create policy "account_deletion_access_guard" on public.company_module_settings as restrictive for all to authenticated using (( SELECT private.account_access_allowed() AS account_access_allowed)) with check (( SELECT private.account_access_allowed() AS account_access_allowed));
create policy "company members can read module settings" on public.company_module_settings as permissive for select to authenticated using ((EXISTS ( SELECT 1
   FROM company_members cm
  WHERE ((cm.company_id = company_module_settings.company_id) AND (cm.user_id = ( SELECT auth.uid() AS uid))))));
create policy "owners and admins can insert module settings" on public.company_module_settings as permissive for insert to authenticated with check (((updated_by = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM company_members cm
  WHERE ((cm.company_id = company_module_settings.company_id) AND (cm.user_id = ( SELECT auth.uid() AS uid)) AND ((cm.role)::text = ANY (ARRAY['owner'::text, 'admin'::text])))))));
create policy "owners and admins can update module settings" on public.company_module_settings as permissive for update to authenticated using ((EXISTS ( SELECT 1
   FROM company_members cm
  WHERE ((cm.company_id = company_module_settings.company_id) AND (cm.user_id = ( SELECT auth.uid() AS uid)) AND ((cm.role)::text = ANY (ARRAY['owner'::text, 'admin'::text])))))) with check (((updated_by = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM company_members cm
  WHERE ((cm.company_id = company_module_settings.company_id) AND (cm.user_id = ( SELECT auth.uid() AS uid)) AND ((cm.role)::text = ANY (ARRAY['owner'::text, 'admin'::text])))))));
