create policy custom_chat_photo_insert on storage.objects as permissive for INSERT to authenticated with check (((bucket_id = 'custom-chat-photos'::text) AND (split_part(name, '/'::text, 2) = (auth.uid())::text) AND (EXISTS ( SELECT 1
   FROM communication_groups g
  WHERE (((g.id)::text = split_part(g.name, '/'::text, 1)) AND private.can_edit_custom_chat_photo(g.id))))));

create policy custom_chat_photo_insert_boundary on storage.objects as restrictive for INSERT to authenticated with check (((bucket_id <> 'custom-chat-photos'::text) OR ((split_part(name, '/'::text, 2) = (auth.uid())::text) AND (EXISTS ( SELECT 1
   FROM communication_groups g
  WHERE (((g.id)::text = split_part(g.name, '/'::text, 1)) AND private.can_edit_custom_chat_photo(g.id)))))));

create policy custom_chat_photo_no_anon on storage.objects as restrictive for ALL to anon using ((bucket_id <> 'custom-chat-photos'::text)) with check ((bucket_id <> 'custom-chat-photos'::text));

create policy custom_chat_photo_no_delete on storage.objects as restrictive for DELETE to authenticated using ((bucket_id <> 'custom-chat-photos'::text));

create policy custom_chat_photo_no_update on storage.objects as restrictive for UPDATE to authenticated using ((bucket_id <> 'custom-chat-photos'::text)) with check ((bucket_id <> 'custom-chat-photos'::text));

create policy custom_chat_photo_read on storage.objects as permissive for SELECT to authenticated using (((bucket_id = 'custom-chat-photos'::text) AND (EXISTS ( SELECT 1
   FROM communication_groups g
  WHERE (((g.id)::text = split_part(g.name, '/'::text, 1)) AND private.can_access_communication_group(g.id))))));

create policy custom_chat_photo_read_boundary on storage.objects as restrictive for SELECT to authenticated using (((bucket_id <> 'custom-chat-photos'::text) OR (EXISTS ( SELECT 1
   FROM communication_groups g
  WHERE (((g.id)::text = split_part(g.name, '/'::text, 1)) AND private.can_access_communication_group(g.id))))));
