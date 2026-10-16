-- Staged only, not a migration. No existing function or row is replaced.
create schema route_atomic_private;
revoke all on schema route_atomic_private from public,anon,authenticated;
create table route_atomic_private.rollout(company_id uuid primary key references public.companies(id),enabled boolean not null default false);
create table route_atomic_private.context(tx bigint not null,pid integer not null,company_id uuid not null,route_id uuid not null,actor uuid not null,primary key(tx,pid));
create table route_atomic_private.receipts(company_id uuid not null,command_id uuid not null,actor uuid not null,request jsonb not null,result jsonb not null,primary key(company_id,command_id));
alter table route_atomic_private.rollout enable row level security;
alter table route_atomic_private.context enable row level security;
alter table route_atomic_private.receipts enable row level security;
revoke all on all tables in schema route_atomic_private from public,anon,authenticated;

create function route_atomic_private.guard() returns trigger language plpgsql security definer set search_path='' as $$
declare rowdata jsonb; cid uuid; rid uuid; enabled boolean; old_cid uuid; old_rid uuid;
begin
 rowdata:=case when TG_OP='DELETE' then to_jsonb(OLD) else to_jsonb(NEW) end;
 cid:=(rowdata->>'company_id')::uuid;
 rid:=case when TG_TABLE_NAME='route_stops' then (rowdata->>'route_assignment_id')::uuid else (rowdata->>'id')::uuid end;
 if TG_OP='UPDATE' then
 old_cid:=(to_jsonb(OLD)->>'company_id')::uuid;
 old_rid:=case when TG_TABLE_NAME='route_stops' then (to_jsonb(OLD)->>'route_assignment_id')::uuid else (to_jsonb(OLD)->>'id')::uuid end;
 end if;
 -- Lock both tenant scopes in stable order; an ON row cannot be moved to OFF.
 insert into route_atomic_private.rollout(company_id)
 select distinct v from (values(cid),(old_cid)) x(v) where v is not null order by v on conflict do nothing;
 perform 1 from route_atomic_private.rollout where company_id in(cid,old_cid) order by company_id for share;
 if TG_OP='UPDATE' and (old_cid<>cid or old_rid<>rid) and exists(select 1 from route_atomic_private.rollout z where z.company_id in(cid,old_cid) and z.enabled) then
 raise exception 'atomic route identity cannot move' using errcode='55000';end if;
 select r.enabled into enabled from route_atomic_private.rollout r where company_id=cid;
 if enabled and not exists(select 1 from route_atomic_private.context c where
 c.tx=txid_current() and c.pid=pg_backend_pid() and c.company_id=cid and c.route_id=rid and c.actor=auth.uid()) then
 raise exception 'atomic route API required while enabled' using errcode='55000';end if;
 if TG_OP='DELETE' then return OLD;end if;
 return NEW;
end $$;
revoke all on function route_atomic_private.guard() from public,anon,authenticated;
create trigger zz_route_atomic_guard before insert or update or delete on public.route_assignments for each row execute function route_atomic_private.guard();
create trigger zz_route_atomic_guard before insert or update or delete on public.route_stops for each row execute function route_atomic_private.guard();

create function route_atomic_private.snapshot(p_company uuid,p_route uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('route',to_jsonb(r),'stops',coalesce(
 (select jsonb_agg(to_jsonb(s) order by s.stop_order,s.id) from public.route_stops s where s.route_assignment_id=r.id and s.company_id=p_company),'[]'))
 from public.route_assignments r where r.id=p_route and r.company_id=p_company
$$;
revoke all on function route_atomic_private.snapshot(uuid,uuid) from public,anon,authenticated;

create function route_atomic_private.save(p_company uuid,p_command uuid,p_route uuid,
 p_expected jsonb,p_data jsonb,p_stops jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); rid uuid:=p_route; request jsonb; old_receipt route_atomic_private.receipts;
 current_doc jsonb; result jsonb; enabled boolean; v jsonb; sid uuid; source uuid; kind text;
 ord integer; old_stop public.route_stops; wanted uuid[]:='{}'; new_ids uuid[]:='{}'; normalized jsonb:='[]';
 lat double precision; lon double precision; offset_order integer;
begin
 if uid is null or not private.account_access_allowed() or not private.can_manage_vehicle_routes(p_company,'route') then
 raise exception 'route management required' using errcode='42501';end if;
 perform private.require_master_optional_feature('route_assignment');
 if p_command is null or p_company is null or p_data is null or jsonb_typeof(p_data)<>'object'
 or p_stops is null or jsonb_typeof(p_stops)<>'array' or jsonb_array_length(p_stops)>100 then
 raise exception 'invalid route command' using errcode='22023';end if;
 if exists(select 1 from jsonb_object_keys(p_data) k where k not in('route_name','notes','responsible_name','responsible_phone')) then
 raise exception 'unsupported route fields' using errcode='22023';end if;
 if char_length(btrim(coalesce(p_data->>'route_name',''))) not between 1 and 120
 or char_length(coalesce(p_data->>'notes',''))>2000 or char_length(coalesce(p_data->>'responsible_name',''))>120
 or char_length(coalesce(p_data->>'responsible_phone',''))>40 then raise exception 'invalid text length' using errcode='22023';end if;
 request:=jsonb_build_object('route',p_route,'expected',p_expected,'data',p_data,'stops',p_stops);
 perform pg_advisory_xact_lock(hashtextextended('route-atomic-command:'||p_company||':'||p_command,0));
 select * into old_receipt from route_atomic_private.receipts where company_id=p_company and command_id=p_command;
 if found then
 if old_receipt.actor<>uid or old_receipt.request<>request then raise exception 'command mismatch' using errcode='22023';end if;
 return old_receipt.result;
 end if;
 insert into route_atomic_private.rollout(company_id) values(p_company) on conflict do nothing;
 select r.enabled into enabled from route_atomic_private.rollout r where r.company_id=p_company for share;
 if not enabled then raise exception 'atomic route rollout off' using errcode='55000';end if;
 perform 1 from public.company_members where company_id=p_company and user_id=uid for share;
 if not private.account_access_allowed() or not private.can_manage_vehicle_routes(p_company,'route') then raise exception 'route management changed' using errcode='42501';end if;
 if rid is null then
 if p_expected is not null then raise exception 'new route has no expected snapshot' using errcode='22023';end if;
 rid:=gen_random_uuid();
 else
 perform 1 from public.route_assignments where id=rid and company_id=p_company for update;
 if not found then raise exception 'route not owned by company' using errcode='42501';end if;
 perform 1 from public.route_stops where route_assignment_id=rid order by stop_order,id for update;
 current_doc:=route_atomic_private.snapshot(p_company,rid);
 if p_expected is null or p_expected is distinct from current_doc then raise exception 'route revision changed' using errcode='40001';end if;
 end if;
 -- Normalize order from the array; stop IDs are never taken from another route.
 for v,ord in select value,(ordinality-1)::integer from jsonb_array_elements(p_stops) with ordinality loop
 if jsonb_typeof(v)<>'object' or exists(select 1 from jsonb_object_keys(v) k where k not in('id','site_id','address','source_kind','source_id','source_label','latitude','longitude')) then
 raise exception 'invalid stop fields' using errcode='22023';end if;
 sid:=nullif(v->>'id','')::uuid;
 if sid is not null then
 select * into old_stop from public.route_stops where id=sid and company_id=p_company and route_assignment_id=rid;
 if not found or sid=any(wanted) then raise exception 'stop identity mismatch' using errcode='42501';end if;
 else sid:=gen_random_uuid();new_ids:=array_append(new_ids,sid);end if;
 wanted:=array_append(wanted,sid);source:=nullif(v->>'source_id','')::uuid;kind:=nullif(v->>'source_kind','');
 if kind is null and source is not null then raise exception 'source kind required' using errcode='22023';end if;
 if kind is not null and kind not in('site','customer','partner','parking','address') then raise exception 'stop kind invalid' using errcode='22023';end if;
 if nullif(v->>'site_id','') is not null and not exists(select 1 from public.sites where id=(v->>'site_id')::uuid and company_id=p_company) then raise exception 'foreign site' using errcode='42501';end if;
 if (kind='site' and (source is null or source is distinct from nullif(v->>'site_id','')::uuid))
 or (kind='customer' and not exists(select 1 from public.customers where id=source and company_id=p_company))
 or (kind='partner' and not exists(select 1 from public.partner_companies where id=source and company_id=p_company))
 or (kind='parking' and not exists(select 1 from public.vehicles where id=source and company_id=p_company))
 or (kind in('address') and source is not null) then raise exception 'foreign/invalid stop source' using errcode='42501';end if;
 if nullif(v->>'site_id','') is not null then
 perform 1 from public.sites where id=(v->>'site_id')::uuid and company_id=p_company for share;
 if not found then raise exception 'site ownership changed' using errcode='42501';end if;end if;
 if kind='customer' then perform 1 from public.customers where id=source and company_id=p_company for share;
 elsif kind='partner' then perform 1 from public.partner_companies where id=source and company_id=p_company for share;
 elsif kind='parking' then perform 1 from public.vehicles where id=source and company_id=p_company for share;
 end if;
 if kind in('customer','partner','parking') and not found then raise exception 'source ownership changed' using errcode='42501';end if;
 if nullif(v->>'site_id','') is null and nullif(btrim(v->>'address'),'') is null then raise exception 'stop needs site/address' using errcode='22023';end if;
 lat:=nullif(v->>'latitude','')::double precision;lon:=nullif(v->>'longitude','')::double precision;
 if (lat is null)<>(lon is null) or (lat is not null and not(lat between -90 and 90 and lon between -180 and 180)) then raise exception 'coordinates invalid' using errcode='22023';end if;
 normalized:=normalized||jsonb_build_array(jsonb_build_object('id',sid,'stop_order',ord,'site_id',nullif(v->>'site_id','')::uuid,
 'address',nullif(btrim(v->>'address'),''),'source_kind',kind,'source_id',source,'source_label',nullif(btrim(v->>'source_label'),''),
 'latitude',lat,'longitude',lon));
 end loop;
 -- Attendance can start capturing a stop later; freeze the whole stop plan once used.
 if p_route is not null and (exists(select 1 from public.attendance_verifications where company_id=p_company and route_assignment_id=rid)
 or exists(select 1 from public.daily_reports where company_id=p_company and route_assignment_id=rid)) and normalized is distinct from
 (select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'stop_order',s.stop_order,'site_id',s.site_id,'address',s.address,'source_kind',s.source_kind,'source_id',s.source_id,'source_label',s.source_label,'latitude',s.latitude,'longitude',s.longitude) order by s.stop_order,s.id),'[]') from public.route_stops s where s.company_id=p_company and s.route_assignment_id=rid) then
 raise exception 'used route stop plan is immutable' using errcode='55000';end if;
 -- History stops cannot be deleted, reordered or edited. Existing IDs survive.
 for old_stop in select * from public.route_stops where route_assignment_id=rid and company_id=p_company loop
 if exists(select 1 from private.route_journey_captures where route_assignment_id=rid and route_stop_id=old_stop.id)
 or exists(select 1 from private.route_visit_reports where route_assignment_id=rid and route_stop_id=old_stop.id) then
 select value into v from jsonb_array_elements(normalized) where value->>'id'=old_stop.id::text;
 if not found or v is distinct from jsonb_build_object('id',old_stop.id,'stop_order',old_stop.stop_order,'site_id',old_stop.site_id,
 'address',old_stop.address,'source_kind',old_stop.source_kind,'source_id',old_stop.source_id,'source_label',old_stop.source_label,
 'latitude',old_stop.latitude,'longitude',old_stop.longitude) then raise exception 'referenced stop immutable' using errcode='55000';end if;
 end if;end loop;
 select coalesce(max(stop_order),0)+101 into offset_order from public.route_stops where route_assignment_id=rid;
 if offset_order>1000000000 then raise exception 'stop order range unsupported' using errcode='22023';end if;
 insert into route_atomic_private.context values(txid_current(),pg_backend_pid(),p_company,rid,uid);
 if p_route is null then
 insert into public.route_assignments(id,company_id,service_date,route_name,notes,responsible_name,responsible_phone,created_by,updated_by)
 values(rid,p_company,null,btrim(p_data->>'route_name'),nullif(btrim(p_data->>'notes'),''),nullif(btrim(p_data->>'responsible_name'),''),nullif(btrim(p_data->>'responsible_phone'),''),uid,uid);
 else
 update public.route_assignments set route_name=btrim(p_data->>'route_name'),notes=nullif(btrim(p_data->>'notes'),''),
 responsible_name=case when p_data?'responsible_name' then nullif(btrim(p_data->>'responsible_name'),'') else responsible_name end,
 responsible_phone=case when p_data?'responsible_phone' then nullif(btrim(p_data->>'responsible_phone'),'') else responsible_phone end,updated_by=uid where id=rid and company_id=p_company;
 end if;
 delete from public.route_stops where route_assignment_id=rid and company_id=p_company and not(id=any(wanted));
 -- Reserve temporary order space only for actually reordered rows. IDs stay fixed.
 update public.route_stops s set stop_order=s.stop_order+offset_order
 where s.route_assignment_id=rid and s.company_id=p_company and exists(select 1 from jsonb_array_elements(normalized) n
 where n->>'id'=s.id::text and (n->>'stop_order')::integer<>s.stop_order);
 for v in select value from jsonb_array_elements(normalized) loop
 sid:=(v->>'id')::uuid;
 if sid=any(new_ids) then
 insert into public.route_stops(id,company_id,route_assignment_id,stop_order,site_id,address,source_kind,source_id,source_label,latitude,longitude,created_by,updated_by)
 values(sid,p_company,rid,(v->>'stop_order')::integer,(v->>'site_id')::uuid,v->>'address',v->>'source_kind',(v->>'source_id')::uuid,v->>'source_label',(v->>'latitude')::double precision,(v->>'longitude')::double precision,uid,uid);
 else
 update public.route_stops s set stop_order=(v->>'stop_order')::integer,site_id=(v->>'site_id')::uuid,address=v->>'address',
 source_kind=v->>'source_kind',source_id=(v->>'source_id')::uuid,source_label=v->>'source_label',
 latitude=(v->>'latitude')::double precision,longitude=(v->>'longitude')::double precision,updated_by=uid
 where s.id=sid and s.company_id=p_company and
 jsonb_build_object('id',s.id,'stop_order',s.stop_order,'site_id',s.site_id,'address',s.address,'source_kind',s.source_kind,'source_id',s.source_id,'source_label',s.source_label,'latitude',s.latitude,'longitude',s.longitude) is distinct from v;
 end if;end loop;
 result:=route_atomic_private.snapshot(p_company,rid);
 insert into route_atomic_private.receipts values(p_company,p_command,uid,request,result);
 delete from route_atomic_private.context where tx=txid_current() and pid=pg_backend_pid();
 return result;
end $$;
revoke all on function route_atomic_private.save(uuid,uuid,uuid,jsonb,jsonb,jsonb) from public,anon,authenticated;
-- Client grants/public wrapper and UI connection intentionally absent.

