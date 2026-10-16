-- STAGED ONLY: apply AFTER the exact df73d422 site_identity_links.sql.
-- No legacy tables, original source file, public API or company rollout is enabled here.
begin;
do $prerequisites$
begin
 if to_regclass('site_identity_private.roots') is null
 or to_regclass('site_identity_private.selections') is null
 or to_regclass('site_identity_private.events') is null then
 raise exception 'site identity base prerequisites missing'; end if;
 if to_regprocedure('site_identity_private.change_link(uuid,uuid,uuid,bigint,boolean)') is null
 or to_regprocedure('site_identity_private.lookup(uuid,text)') is null
 or to_regprocedure('site_identity_private.admin(uuid)') is null then
 raise exception 'site identity base RPCs missing'; end if;
end $prerequisites$;
do $base_dependencies$
begin
 if not exists(select 1 from pg_proc where oid=to_regprocedure('site_identity_private.admin(uuid)') and md5(prosrc)='0d9ac1b8f91b8e8fc0eafa636b2ecbcf') then raise exception 'site identity dependency drift: site_identity_private.admin';end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('site_identity_private.ensure_root(uuid,uuid)') and md5(prosrc)='1148357aec96e583d36d4274c1b9b32d') then raise exception 'site identity dependency drift: site_identity_private.ensure_root';end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('public.site_identity_change_link(uuid,uuid,uuid,bigint,boolean)') and md5(prosrc)='a2f247e640707677756f406f751ed63b') then raise exception 'site identity dependency drift: public.site_identity_change_link';end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('public.site_identity_lookup(uuid,text)') and md5(prosrc)='41f5eaf9decc75d9ac3e856b3d61498b') then raise exception 'site identity dependency drift: public.site_identity_lookup';end if;
end $base_dependencies$;


create table if not exists site_identity_private.company_rollout(
 company_id uuid primary key,
 enabled boolean not null default false,
 changed_by uuid not null,
 changed_at timestamptz not null default clock_timestamp());
create table if not exists site_identity_private.rollout_events(
 id bigint generated always as identity primary key,
 company_id uuid not null,
 before_enabled boolean not null,
 after_enabled boolean not null,
 actor_id uuid not null,
 changed_at timestamptz not null default clock_timestamp());
alter table site_identity_private.company_rollout enable row level security;
alter table site_identity_private.rollout_events enable row level security;
revoke all on site_identity_private.company_rollout,site_identity_private.rollout_events from public,anon,authenticated;

create or replace function site_identity_private.require_rollout(p_company uuid)
returns void language plpgsql stable security definer set search_path='' as $fn$
begin
 if not exists(select 1 from site_identity_private.company_rollout
  where company_id=p_company and enabled) then
 raise exception 'site identity rollout disabled' using errcode='55000'; end if;
end $fn$;

-- Unexposed-schema SQL helper, NOT a public/PostgREST settings endpoint.
-- authenticated SQL callers still require owner/admin membership in this company.
create or replace function site_identity_private.set_rollout(p_company uuid,p_enabled boolean)
returns jsonb language plpgsql security definer set search_path='' as $fn$
declare previous boolean:=false;
begin
 perform site_identity_private.admin(p_company);
 if p_enabled is null then raise exception 'rollout boolean required' using errcode='22023'; end if;
 -- Same registry-only lock as change_link; no legacy business locks are acquired.
 perform pg_advisory_xact_lock(hashtextextended('site-identity-registry',0));
 perform site_identity_private.admin(p_company);
 select enabled into previous from site_identity_private.company_rollout where company_id=p_company;
 previous:=coalesce(previous,false);
 insert into site_identity_private.company_rollout(company_id,enabled,changed_by)
 values(p_company,p_enabled,auth.uid()) on conflict(company_id) do update
 set enabled=excluded.enabled,changed_by=excluded.changed_by,changed_at=clock_timestamp()
 where company_rollout.enabled is distinct from excluded.enabled;
 if previous is distinct from p_enabled then
 insert into site_identity_private.rollout_events(company_id,before_enabled,after_enabled,actor_id)
 values(p_company,previous,p_enabled,auth.uid());
 end if;
 return jsonb_build_object('company_id',p_company,'enabled',p_enabled);
end $fn$;
revoke all on function site_identity_private.require_rollout(uuid),
 site_identity_private.set_rollout(uuid,boolean) from public,anon,authenticated;
grant execute on function site_identity_private.set_rollout(uuid,boolean) to authenticated;

do $patch$
declare target regprocedure:='site_identity_private.change_link(uuid,uuid,uuid,bigint,boolean)'::regprocedure; original text; definition text;
begin
 select prosrc,pg_get_functiondef(oid) into original,definition from pg_proc where oid=target;
 if original='
-- site_identity_company_rollout_v1

declare ownroot uuid; targetroot uuid; voteroot uuid; previous uuid; rev bigint; source_site uuid; source_company uuid; proof record;
begin
 perform site_identity_private.admin(p_company);
 -- Serialize this isolated registry only; never lock/update legacy attendance sources.
 perform pg_advisory_xact_lock(hashtextextended(''site-identity-registry'',0));
 perform site_identity_private.require_rollout(p_company);
 ownroot:=site_identity_private.ensure_root(p_company,p_site);
 select display_group,revision into previous,rev from site_identity_private.selections where site_id=p_site and company_id=p_company for update;
 if rev<>p_expected_revision or p_expected_revision is null then raise exception ''stale selection'' using errcode=''40001'';end if;
 if p_unlink then targetroot:=ownroot; voteroot:=ownroot;
 else
 select s.recipient_company_id,s.status,d.sender_company_id,d.recipient_company_id as delivery_recipient,i.payload_kind,i.payload into proof
 from private.site_share_inbox s join private.company_data_delivery_items i on i.id=s.data_item_id
 join private.document_deliveries d on d.id=i.delivery_id where s.data_item_id=p_delivery;
 if proof.recipient_company_id is distinct from p_company or proof.delivery_recipient is distinct from p_company
 or proof.status not in (''pending'',''accepted'') or proof.payload_kind is distinct from ''site_share'' then
 raise exception ''received site share required'' using errcode=''42501'';end if;
 source_site:=(proof.payload->>''source_site_id'')::uuid; source_company:=proof.sender_company_id;
 if source_company=p_company or source_site is null then raise exception ''invalid share source'';end if;
 -- Sender ownership is verified against the server site, never payload company names.
 perform site_identity_private.require_rollout(source_company);
 perform site_identity_private.ensure_root(source_company,source_site);
 select display_group,home_root into targetroot,voteroot from site_identity_private.selections where site_id=source_site and company_id=source_company;
 -- Existing membership may only be changed by its owner. Other memberships remain untouched.
 end if;
 if targetroot<>previous or voteroot is distinct from (select vote_root from site_identity_private.selections where site_id=p_site) then
 update site_identity_private.selections set display_group=targetroot,vote_root=voteroot,revision=revision+1 where site_id=p_site and company_id=p_company returning revision into rev;
 insert into site_identity_private.events(company_id,site_id,before_group,after_group,delivery_item_id,actor_id)
 values(p_company,p_site,previous,targetroot,case when p_unlink then null else p_delivery end,auth.uid());
 end if;
 return jsonb_build_object(''site_id'',p_site,''display_group'',targetroot,''revision'',rev);
end ' then return; end if;
 if md5(original)<>'1e4e8530eb7762c1ce1febb952365e30' then raise exception 'site identity definition drift: change_link'; end if;
 execute replace(definition,original,'
-- site_identity_company_rollout_v1

declare ownroot uuid; targetroot uuid; voteroot uuid; previous uuid; rev bigint; source_site uuid; source_company uuid; proof record;
begin
 perform site_identity_private.admin(p_company);
 -- Serialize this isolated registry only; never lock/update legacy attendance sources.
 perform pg_advisory_xact_lock(hashtextextended(''site-identity-registry'',0));
 perform site_identity_private.require_rollout(p_company);
 ownroot:=site_identity_private.ensure_root(p_company,p_site);
 select display_group,revision into previous,rev from site_identity_private.selections where site_id=p_site and company_id=p_company for update;
 if rev<>p_expected_revision or p_expected_revision is null then raise exception ''stale selection'' using errcode=''40001'';end if;
 if p_unlink then targetroot:=ownroot; voteroot:=ownroot;
 else
 select s.recipient_company_id,s.status,d.sender_company_id,d.recipient_company_id as delivery_recipient,i.payload_kind,i.payload into proof
 from private.site_share_inbox s join private.company_data_delivery_items i on i.id=s.data_item_id
 join private.document_deliveries d on d.id=i.delivery_id where s.data_item_id=p_delivery;
 if proof.recipient_company_id is distinct from p_company or proof.delivery_recipient is distinct from p_company
 or proof.status not in (''pending'',''accepted'') or proof.payload_kind is distinct from ''site_share'' then
 raise exception ''received site share required'' using errcode=''42501'';end if;
 source_site:=(proof.payload->>''source_site_id'')::uuid; source_company:=proof.sender_company_id;
 if source_company=p_company or source_site is null then raise exception ''invalid share source'';end if;
 -- Sender ownership is verified against the server site, never payload company names.
 perform site_identity_private.require_rollout(source_company);
 perform site_identity_private.ensure_root(source_company,source_site);
 select display_group,home_root into targetroot,voteroot from site_identity_private.selections where site_id=source_site and company_id=source_company;
 -- Existing membership may only be changed by its owner. Other memberships remain untouched.
 end if;
 if targetroot<>previous or voteroot is distinct from (select vote_root from site_identity_private.selections where site_id=p_site) then
 update site_identity_private.selections set display_group=targetroot,vote_root=voteroot,revision=revision+1 where site_id=p_site and company_id=p_company returning revision into rev;
 insert into site_identity_private.events(company_id,site_id,before_group,after_group,delivery_item_id,actor_id)
 values(p_company,p_site,previous,targetroot,case when p_unlink then null else p_delivery end,auth.uid());
 end if;
 return jsonb_build_object(''site_id'',p_site,''display_group'',targetroot,''revision'',rev);
end ');
end $patch$;

do $patch$
declare target regprocedure:='site_identity_private.lookup(uuid,text)'::regprocedure; original text; definition text;
begin
 select prosrc,pg_get_functiondef(oid) into original,definition from pg_proc where oid=target;
 if original='
-- site_identity_company_rollout_v1

begin
 perform site_identity_private.admin(p_company);
 perform site_identity_private.require_rollout(p_company);
 if p_query is null or length(trim(p_query))<1 or length(p_query)>200 then raise exception ''exact name or ID required'';end if;
 return coalesce((select jsonb_agg(jsonb_build_object(''local_site_id'',s.id,''formal_name'',coalesce(nullif(s.formal_name,''''),s.name),''display_group'',m.display_group,''revision'',m.revision,
 ''representative_id'',(select r.id from site_identity_private.roots r join site_identity_private.selections v on v.vote_root=r.id where v.display_group=m.display_group group by r.id,r.created_at order by count(distinct v.company_id) desc,r.created_at,r.id limit 1)))
 from public.sites s left join site_identity_private.selections m on m.site_id=s.id and m.company_id=p_company
 where s.company_id=p_company and (coalesce(nullif(s.formal_name,''''),s.name)=trim(p_query) or s.id::text=trim(p_query) or m.home_root::text=trim(p_query) or m.display_group::text=trim(p_query))),''[]''::jsonb);
end ' then return; end if;
 if md5(original)<>'1cac75b0de5afbfa03a4283dcb2f04ed' then raise exception 'site identity definition drift: lookup'; end if;
 execute replace(definition,original,'
-- site_identity_company_rollout_v1

begin
 perform site_identity_private.admin(p_company);
 perform site_identity_private.require_rollout(p_company);
 if p_query is null or length(trim(p_query))<1 or length(p_query)>200 then raise exception ''exact name or ID required'';end if;
 return coalesce((select jsonb_agg(jsonb_build_object(''local_site_id'',s.id,''formal_name'',coalesce(nullif(s.formal_name,''''),s.name),''display_group'',m.display_group,''revision'',m.revision,
 ''representative_id'',(select r.id from site_identity_private.roots r join site_identity_private.selections v on v.vote_root=r.id where v.display_group=m.display_group group by r.id,r.created_at order by count(distinct v.company_id) desc,r.created_at,r.id limit 1)))
 from public.sites s left join site_identity_private.selections m on m.site_id=s.id and m.company_id=p_company
 where s.company_id=p_company and (coalesce(nullif(s.formal_name,''''),s.name)=trim(p_query) or s.id::text=trim(p_query) or m.home_root::text=trim(p_query) or m.display_group::text=trim(p_query))),''[]''::jsonb);
end ');
end $patch$;
commit;
-- Operations:
-- This supplement has no initial enabled rows. Missing setting means OFF.
-- OFF freezes selections/events, and blocks lookup/link/unlink without deleting IDs.
-- Re-enable to resume existing selections; unlink remains the original ON-only CAS.
-- The receiver and sender must both be ON before a link creates sender registry rows.
-- Lookup started before a concurrent OFF may finish under its original read snapshot.
-- SQL owner administration and application company administration are different:
-- this helper is authenticated SQL-only, owner/admin scoped, with no public wrapper.
-- Do not expose site_identity_private as an additional PostgREST schema.
-- A DB owner can inspect/change settings through controlled staging SQL; such direct
-- privileged SQL is outside application authorization and must be independently audited.
-- No production application, public settings API, notification or cron operation here.
