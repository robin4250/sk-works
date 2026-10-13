-- Fix four object-path references without changing policy roles or restrictive boundaries.
begin;
set local search_path=public,pg_catalog;
do $guard$ begin
 if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='custom_chat_photo_insert' and cmd='INSERT' and permissive='PERMISSIVE' and roles=ARRAY['authenticated']::name[] and md5(regexp_replace(with_check,'\s','','g')) in ('20885a8dbe948ec927ec6ac63a7f20ac','91c413da33ac3b7226bc6b226a41bcca')) then raise exception 'chat photo policy prerequisite differs: custom_chat_photo_insert';end if;
 if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='custom_chat_photo_insert_boundary' and cmd='INSERT' and permissive='RESTRICTIVE' and roles=ARRAY['authenticated']::name[] and md5(regexp_replace(with_check,'\s','','g')) in ('909828e60a67308c45c8e374b2e6b9ca','152b212b8b121f0315b09e98dd1c0679')) then raise exception 'chat photo policy prerequisite differs: custom_chat_photo_insert_boundary';end if;
 if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='custom_chat_photo_read' and cmd='SELECT' and permissive='PERMISSIVE' and roles=ARRAY['authenticated']::name[] and md5(regexp_replace(qual,'\s','','g')) in ('c22599ac61a9fe6082a212df13cdbdf3','9f282ed0aed99c3e5f9c37d1150b8944')) then raise exception 'chat photo policy prerequisite differs: custom_chat_photo_read';end if;
 if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='custom_chat_photo_read_boundary' and cmd='SELECT' and permissive='RESTRICTIVE' and roles=ARRAY['authenticated']::name[] and md5(regexp_replace(qual,'\s','','g')) in ('87a5f5c6e3b54e9bb909a2571b48f213','21e1a09d55e611ef34f619718dec0fe3')) then raise exception 'chat photo policy prerequisite differs: custom_chat_photo_read_boundary';end if;
end $guard$;

alter policy custom_chat_photo_insert on storage.objects with check (((bucket_id = 'custom-chat-photos'::text) AND (split_part(objects.name, '/'::text, 2) = (auth.uid())::text) AND (EXISTS ( SELECT 1
   FROM public.communication_groups g
  WHERE (((g.id)::text = split_part(objects.name, '/'::text, 1)) AND private.can_edit_custom_chat_photo(g.id))))));

alter policy custom_chat_photo_insert_boundary on storage.objects with check (((bucket_id <> 'custom-chat-photos'::text) OR ((split_part(objects.name, '/'::text, 2) = (auth.uid())::text) AND (EXISTS ( SELECT 1
   FROM public.communication_groups g
  WHERE (((g.id)::text = split_part(objects.name, '/'::text, 1)) AND private.can_edit_custom_chat_photo(g.id)))))));

alter policy custom_chat_photo_read on storage.objects using (((bucket_id = 'custom-chat-photos'::text) AND (EXISTS ( SELECT 1
   FROM public.communication_groups g
  WHERE (((g.id)::text = split_part(objects.name, '/'::text, 1)) AND private.can_access_communication_group(g.id))))));

alter policy custom_chat_photo_read_boundary on storage.objects using (((bucket_id <> 'custom-chat-photos'::text) OR (EXISTS ( SELECT 1
   FROM public.communication_groups g
  WHERE (((g.id)::text = split_part(objects.name, '/'::text, 1)) AND private.can_access_communication_group(g.id))))));
commit;
