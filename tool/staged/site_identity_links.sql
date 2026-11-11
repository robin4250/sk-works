-- Fail closed on prerequisites; this file never guesses a replacement legacy schema.
do $$begin
 if to_regclass('public.sites') is null or to_regclass('public.company_members') is null
 or to_regclass('private.site_share_inbox') is null or to_regclass('private.document_deliveries') is null
 or to_regclass('private.company_data_delivery_items') is null then raise exception 'site identity prerequisites differ';end if;
 perform id,company_id,name,formal_name from public.sites limit 0;
 perform company_id,user_id,role from public.company_members limit 0;
 perform data_item_id,recipient_company_id,status from private.site_share_inbox limit 0;
 perform id,sender_company_id,recipient_company_id from private.document_deliveries limit 0;
 perform id,delivery_id,payload_kind,payload from private.company_data_delivery_items limit 0;
end $$;
-- STAGED ONLY. No site, attendance, image, contract, permission or notification writes.
-- A company selects a display group for its own local site. No group-wide merge.
-- Global discovery and reassignment/merging of existing groups are intentionally absent.
create schema site_identity_private;
revoke all on schema site_identity_private from public,anon,authenticated;
create table site_identity_private.roots(
 id uuid primary key default gen_random_uuid(), company_id uuid not null,
 site_id uuid not null unique, created_at timestamptz not null default now()
);
create table site_identity_private.selections(
 site_id uuid primary key, company_id uuid not null, home_root uuid not null references site_identity_private.roots(id),
 vote_root uuid not null references site_identity_private.roots(id), display_group uuid not null references site_identity_private.roots(id), revision bigint not null default 0
);
create table site_identity_private.events(
 id bigint generated always as identity primary key, company_id uuid not null, site_id uuid not null,
 before_group uuid not null, after_group uuid not null, delivery_item_id uuid,
 actor_id uuid not null, created_at timestamptz not null default now()
);
alter table site_identity_private.roots enable row level security;
alter table site_identity_private.selections enable row level security;
alter table site_identity_private.events enable row level security;
-- No foreign-key delete cascade: history survives legacy site/company deletion.
create function site_identity_private.admin(p_company uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not exists(select 1 from public.company_members where company_id=p_company and user_id=auth.uid() and role::text in ('owner','admin')) then
 raise exception 'company administrator required' using errcode='42501'; end if;
end $$;
create function site_identity_private.ensure_root(p_company uuid,p_site uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare rid uuid;
begin
 if not exists(select 1 from public.sites where id=p_site and company_id=p_company) then raise exception 'local site not found' using errcode='42501';end if;
 insert into site_identity_private.roots(company_id,site_id) values(p_company,p_site) on conflict(site_id) do nothing;
 select id into rid from site_identity_private.roots where site_id=p_site and company_id=p_company;
 if rid is null then raise exception 'site ownership changed';end if;
 insert into site_identity_private.selections(site_id,company_id,home_root,vote_root,display_group) values(p_site,p_company,rid,rid,rid) on conflict(site_id) do nothing;
 return rid;
end $$;
create function site_identity_private.change_link(p_company uuid,p_site uuid,p_delivery uuid,p_expected_revision bigint,p_unlink boolean default false) returns jsonb
language plpgsql security definer set search_path='' as $$
declare ownroot uuid; targetroot uuid; voteroot uuid; previous uuid; rev bigint; source_site uuid; source_company uuid; proof record;
begin
 perform site_identity_private.admin(p_company);
 -- Serialize this isolated registry only; never lock/update legacy attendance sources.
 perform pg_advisory_xact_lock(hashtextextended('site-identity-registry',0));
 ownroot:=site_identity_private.ensure_root(p_company,p_site);
 select display_group,revision into previous,rev from site_identity_private.selections where site_id=p_site and company_id=p_company for update;
 if rev<>p_expected_revision or p_expected_revision is null then raise exception 'stale selection' using errcode='40001';end if;
 if p_unlink then targetroot:=ownroot; voteroot:=ownroot;
 else
 select s.recipient_company_id,s.status,d.sender_company_id,d.recipient_company_id as delivery_recipient,i.payload_kind,i.payload into proof
 from private.site_share_inbox s join private.company_data_delivery_items i on i.id=s.data_item_id
 join private.document_deliveries d on d.id=i.delivery_id where s.data_item_id=p_delivery;
 if proof.recipient_company_id is distinct from p_company or proof.delivery_recipient is distinct from p_company
 or proof.status not in ('pending','accepted') or proof.payload_kind is distinct from 'site_share' then
 raise exception 'received site share required' using errcode='42501';end if;
 source_site:=(proof.payload->>'source_site_id')::uuid; source_company:=proof.sender_company_id;
 if source_company=p_company or source_site is null then raise exception 'invalid share source';end if;
 -- Sender ownership is verified against the server site, never payload company names.
 perform site_identity_private.ensure_root(source_company,source_site);
 select display_group,home_root into targetroot,voteroot from site_identity_private.selections where site_id=source_site and company_id=source_company;
 -- Existing membership may only be changed by its owner. Other memberships remain untouched.
 end if;
 if targetroot<>previous or voteroot is distinct from (select vote_root from site_identity_private.selections where site_id=p_site) then
 update site_identity_private.selections set display_group=targetroot,vote_root=voteroot,revision=revision+1 where site_id=p_site and company_id=p_company returning revision into rev;
 insert into site_identity_private.events(company_id,site_id,before_group,after_group,delivery_item_id,actor_id)
 values(p_company,p_site,previous,targetroot,case when p_unlink then null else p_delivery end,auth.uid());
 end if;
 return jsonb_build_object('site_id',p_site,'display_group',targetroot,'revision',rev);
end $$;
create function site_identity_private.lookup(p_company uuid,p_query text) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform site_identity_private.admin(p_company);
 if p_query is null or length(trim(p_query))<1 or length(p_query)>200 then raise exception 'exact name or ID required';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('local_site_id',s.id,'formal_name',coalesce(nullif(s.formal_name,''),s.name),'display_group',m.display_group,'revision',m.revision,
 'representative_id',(select r.id from site_identity_private.roots r join site_identity_private.selections v on v.vote_root=r.id where v.display_group=m.display_group group by r.id,r.created_at order by count(distinct v.company_id) desc,r.created_at,r.id limit 1)))
 from public.sites s left join site_identity_private.selections m on m.site_id=s.id and m.company_id=p_company
 where s.company_id=p_company and (coalesce(nullif(s.formal_name,''),s.name)=trim(p_query) or s.id::text=trim(p_query) or m.home_root::text=trim(p_query) or m.display_group::text=trim(p_query))),'[]'::jsonb);
end $$;
revoke all on all functions in schema site_identity_private from public,anon,authenticated;
grant usage on schema site_identity_private to authenticated;
grant execute on function site_identity_private.change_link(uuid,uuid,uuid,bigint,boolean),site_identity_private.lookup(uuid,text) to authenticated;
create function public.site_identity_change_link(p_company uuid,p_site uuid,p_delivery uuid,p_expected_revision bigint,p_unlink boolean default false) returns jsonb language sql security invoker set search_path='' as $$select site_identity_private.change_link(p_company,p_site,p_delivery,p_expected_revision,p_unlink)$$;
create function public.site_identity_lookup(p_company uuid,p_query text) returns jsonb language sql stable security invoker set search_path='' as $$select site_identity_private.lookup(p_company,p_query)$$;
revoke all on function public.site_identity_change_link(uuid,uuid,uuid,bigint,boolean),public.site_identity_lookup(uuid,text) from public,anon;
grant execute on function public.site_identity_change_link(uuid,uuid,uuid,bigint,boolean),public.site_identity_lookup(uuid,text) to authenticated;
