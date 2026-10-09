-- STAGED ONLY. No data backfill, payroll caller, quantity writer or UI adoption.
-- Replaces #840's derived company+slot identity for LEGACY slots only.
-- Existing name/amount/unit columns remain the single current pricing source.
create schema company_allowance_identity_private;
revoke all on schema company_allowance_identity_private from public,anon,authenticated;
create table company_allowance_identity_private.state (
 company_id uuid primary key, version bigint not null check(version>=1),
 adopted_by uuid not null, adopted_at timestamptz not null default clock_timestamp()
);
create table company_allowance_identity_private.identities (
 id uuid primary key default gen_random_uuid(), company_id uuid not null,
 slot integer not null check(slot between 1 and 3), generation bigint not null check(generation>0),
 created_by uuid not null, created_at timestamptz not null default clock_timestamp(),
 retired_by uuid, retired_at timestamptz,
 unique(company_id,slot,generation), unique(company_id,id),
 check((retired_by is null)=(retired_at is null))
);
create unique index company_allowance_one_active_slot on company_allowance_identity_private.identities(company_id,slot) where retired_at is null;
create table company_allowance_identity_private.history (
 company_id uuid not null,version bigint not null,actor_id uuid not null,
 changed_at timestamptz not null default clock_timestamp(),
 event text not null check(event in ('adopt','settings_update')),
 before_value jsonb,after_value jsonb not null,
 primary key(company_id,version)
);
alter table company_allowance_identity_private.state enable row level security;
alter table company_allowance_identity_private.identities enable row level security;
alter table company_allowance_identity_private.history enable row level security;
revoke all on all tables in schema company_allowance_identity_private from public,anon,authenticated;

-- Pure fixed-field extraction: no generic serialization or second price master.
create function company_allowance_identity_private.slots(r public.company_rate_settings)
returns jsonb language sql immutable set search_path='' as $$
 select jsonb_build_array(
 jsonb_build_object('slot',1,'name',r.allowance_1_name,'unit',r.allowance_1_unit,'amount_yen',r.allowance_1_amount_yen),
 jsonb_build_object('slot',2,'name',r.allowance_2_name,'unit',r.allowance_2_unit,'amount_yen',r.allowance_2_amount_yen),
 jsonb_build_object('slot',3,'name',r.allowance_3_name,'unit',r.allowance_3_unit,'amount_yen',r.allowance_3_amount_yen))
$$;
create function company_allowance_identity_private.authorize(cid uuid,editing boolean)
returns void language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or private.account_access_allowed() is distinct from true
 or not exists(select 1 from public.companies where id=cid)
 or not exists(select 1 from public.company_members where company_id=cid and user_id=auth.uid()
 and (not editing or role::text in ('owner','admin'))) then
 raise exception 'company allowance access denied' using errcode='42501';end if;
end$$;

-- Called while the existing company settings row is locked. Enrollment is explicit.
-- Only blank -> nonblank allocates a new generation; nonblank rename keeps the ID.
create function company_allowance_identity_private.advance(r public.company_rate_settings)
returns void language plpgsql security definer set search_path='' as $$
declare item jsonb; current_id uuid; next_generation bigint;
begin
 for item in select value from jsonb_array_elements(company_allowance_identity_private.slots(r)) loop
  select id into current_id from company_allowance_identity_private.identities
  where company_id=r.company_id and slot=(item->>'slot')::integer and retired_at is null;
  if nullif(btrim(item->>'name'),'') is null then
   if current_id is not null then update company_allowance_identity_private.identities
   set retired_by=auth.uid(),retired_at=clock_timestamp() where id=current_id;end if;
  elsif current_id is null then
   select coalesce(max(generation),0)+1 into next_generation
   from company_allowance_identity_private.identities where company_id=r.company_id and slot=(item->>'slot')::integer;
   insert into company_allowance_identity_private.identities(company_id,slot,generation,created_by)
   values(r.company_id,(item->>'slot')::integer,next_generation,auth.uid());
  end if;
 end loop;
end$$;
create function company_allowance_identity_private.current_value(r public.company_rate_settings)
returns jsonb language sql stable set search_path='' as $$
 select coalesce(jsonb_agg(item||jsonb_build_object('id',i.id,'generation',i.generation) order by i.slot),'[]')
 from jsonb_array_elements(company_allowance_identity_private.slots(r)) item
 join company_allowance_identity_private.identities i on i.company_id=r.company_id and i.slot=(item->>'slot')::integer and i.retired_at is null
$$;

-- Existing writers remain unchanged. Every enrolled row UPDATE advances version;
-- the combined saver updates twice. Old clients must not assume version +1.
create function company_allowance_identity_private.track_settings() returns trigger
language plpgsql security definer set search_path='' as $$
declare v bigint; before_state jsonb;
begin
 if new.company_id is distinct from old.company_id then
  if exists(select 1 from company_allowance_identity_private.state where company_id in (old.company_id,new.company_id)) then
   raise exception 'adopted allowance company identity cannot change';end if;
  return new;
 end if;
 select version into v from company_allowance_identity_private.state where company_id=new.company_id for update;
 if not found then return new;end if;
 perform company_allowance_identity_private.authorize(new.company_id,true);
 before_state:=company_allowance_identity_private.current_value(old);
 perform company_allowance_identity_private.advance(new);
 update company_allowance_identity_private.state set version=v+1 where company_id=new.company_id;
 insert into company_allowance_identity_private.history(company_id,version,actor_id,event,before_value,after_value)
 values(new.company_id,v+1,auth.uid(),'settings_update',before_state,company_allowance_identity_private.current_value(new));
 return new;
end$$;
create trigger company_allowance_identity_track before update on public.company_rate_settings
for each row execute function company_allowance_identity_private.track_settings();

-- Deleting/reinserting settings would otherwise reconnect active IDs to new values.
-- Enrollment stops destructive settings-row replacement while the company exists.
-- Parent-company cascades may remove settings; private history has no cascading FK
-- and remains inaccessible once the company is gone.
create function company_allowance_identity_private.prevent_settings_delete() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from public.companies where id=old.company_id)
 and exists(select 1 from company_allowance_identity_private.state where company_id=old.company_id) then
 raise exception 'adopted allowance settings require explicit retirement before deletion';end if;
 return old;
end$$;
create trigger company_allowance_identity_no_delete before delete on public.company_rate_settings
for each row execute function company_allowance_identity_private.prevent_settings_delete();

-- True INSERT only: does not reject the INSERT side of a legacy ON CONFLICT
-- UPDATE. A deleted/recreated company with the same UUID must not reuse history.
create function company_allowance_identity_private.prevent_reinsert() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from company_allowance_identity_private.state where company_id=new.company_id) then
 raise exception 'adopted allowance company identity cannot be recreated';end if;
 return new;
end$$;
create trigger company_allowance_identity_no_reinsert after insert on public.company_rate_settings
for each row execute function company_allowance_identity_private.prevent_reinsert();

create function company_allowance_identity_private.admin_state(cid uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare r public.company_rate_settings%rowtype; s company_allowance_identity_private.state%rowtype;
begin
 perform company_allowance_identity_private.authorize(cid,true);
 select * into r from public.company_rate_settings where company_id=cid;
 if not found then raise exception 'company allowance settings missing' using errcode='22023';end if;
 select * into s from company_allowance_identity_private.state where company_id=cid;
 return jsonb_build_object('contract_version',1,'company_id',cid,'adopted',s.company_id is not null,'version',coalesce(s.version,0),
 'observed_slots',company_allowance_identity_private.slots(r),'items',company_allowance_identity_private.current_value(r),
 'identities',coalesce((select jsonb_agg(to_jsonb(i) order by slot,generation) from company_allowance_identity_private.identities i where company_id=cid),'[]'),
 'history',coalesce((select jsonb_agg(to_jsonb(h) order by version) from company_allowance_identity_private.history h where company_id=cid),'[]'));
end$$;
create function company_allowance_identity_private.adopt(cid uuid,observed_slots jsonb,confirmed boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.company_rate_settings%rowtype;
begin
 perform company_allowance_identity_private.authorize(cid,true);
 if confirmed is not true then raise exception 'explicit allowance adoption confirmation required' using errcode='22023';end if;
 -- Match the existing rate saver: company first, then settings. Future quantity
 -- integration must add worker/month locks between these, never reverse order.
 perform 1 from public.companies where id=cid for update;
 if not found then raise exception 'company allowance access denied' using errcode='42501';end if;
 select * into r from public.company_rate_settings where company_id=cid for update;
 if not found then raise exception 'company allowance settings missing' using errcode='22023';end if;
 if exists(select 1 from company_allowance_identity_private.state where company_id=cid) then raise exception 'allowance identity already adopted' using errcode='40001';end if;
 if observed_slots is distinct from company_allowance_identity_private.slots(r) then raise exception 'allowance source version conflict' using errcode='40001';end if;
 insert into company_allowance_identity_private.state(company_id,version,adopted_by) values(cid,1,auth.uid());
 perform company_allowance_identity_private.advance(r);
 insert into company_allowance_identity_private.history(company_id,version,actor_id,event,after_value)
 values(cid,1,auth.uid(),'adopt',company_allowance_identity_private.current_value(r));
 return company_allowance_identity_private.admin_state(cid);
end$$;
create function company_allowance_identity_private.labels(cid uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare r public.company_rate_settings%rowtype; v bigint;
begin
 perform company_allowance_identity_private.authorize(cid,false);
 select * into r from public.company_rate_settings where company_id=cid;
 select version into v from company_allowance_identity_private.state where company_id=cid;
 if r.company_id is null or v is null then raise exception 'allowance identity not adopted' using errcode='55000';end if;
 return jsonb_build_object('contract_version',1,'company_id',cid,'version',v,'items',coalesce((
 select jsonb_agg(jsonb_build_object('id',item->>'id','name',item->>'name','unit',item->>'unit','generation',item->'generation') order by item->>'slot')
 from jsonb_array_elements(company_allowance_identity_private.current_value(r)) item),'[]'));
end$$;
create function company_allowance_identity_private.edit_slot(cid uuid,p_slot integer,p_expected_version bigint,p_name text,p_unit text,p_amount_yen integer,p_confirmed boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.company_rate_settings%rowtype;v bigint;
begin
 perform company_allowance_identity_private.authorize(cid,true);
 if p_confirmed is not true or p_slot is null or p_slot not between 1 and 3 or p_name is null or length(btrim(p_name))>80
 or p_unit is null or nullif(btrim(p_unit),'') is null or length(btrim(p_unit))>12 or p_amount_yen is null or p_amount_yen<0 then
 raise exception 'invalid allowance fields or confirmation' using errcode='22023';end if;
 perform 1 from public.companies where id=cid for update;
 if not found then raise exception 'company allowance access denied' using errcode='42501';end if;
 select * into r from public.company_rate_settings where company_id=cid for update;
 select version into v from company_allowance_identity_private.state where company_id=cid;
 if r.company_id is null or v is null then raise exception 'allowance identity not adopted' using errcode='55000';end if;
 if p_expected_version is null or p_expected_version<>v then raise exception 'allowance identity version conflict' using errcode='40001';end if;
 update public.company_rate_settings set
 allowance_1_name=case when p_slot=1 then p_name else allowance_1_name end,
 allowance_1_unit=case when p_slot=1 then p_unit else allowance_1_unit end,
 allowance_1_amount_yen=case when p_slot=1 then p_amount_yen else allowance_1_amount_yen end,
 allowance_2_name=case when p_slot=2 then p_name else allowance_2_name end,
 allowance_2_unit=case when p_slot=2 then p_unit else allowance_2_unit end,
 allowance_2_amount_yen=case when p_slot=2 then p_amount_yen else allowance_2_amount_yen end,
 allowance_3_name=case when p_slot=3 then p_name else allowance_3_name end,
 allowance_3_unit=case when p_slot=3 then p_unit else allowance_3_unit end,
 allowance_3_amount_yen=case when p_slot=3 then p_amount_yen else allowance_3_amount_yen end,
 updated_by=auth.uid(),updated_at=clock_timestamp()
 where company_id=cid;
 return company_allowance_identity_private.admin_state(cid);
end$$;

revoke all on all functions in schema company_allowance_identity_private from public,anon,authenticated;
grant usage on schema company_allowance_identity_private to authenticated;
grant execute on function company_allowance_identity_private.admin_state(uuid),company_allowance_identity_private.adopt(uuid,jsonb,boolean),company_allowance_identity_private.labels(uuid),company_allowance_identity_private.edit_slot(uuid,integer,bigint,text,text,integer,boolean) to authenticated;
create function public.read_company_allowance_identity_admin(p_company_id uuid) returns jsonb
language sql stable security invoker set search_path='' as $$select company_allowance_identity_private.admin_state(p_company_id)$$;
create function public.adopt_company_allowance_identity(p_company_id uuid,p_observed_slots jsonb,p_confirmed boolean) returns jsonb
language sql security invoker set search_path='' as $$select company_allowance_identity_private.adopt(p_company_id,p_observed_slots,p_confirmed)$$;
create function public.read_company_allowance_identity_labels(p_company_id uuid) returns jsonb
language sql stable security invoker set search_path='' as $$select company_allowance_identity_private.labels(p_company_id)$$;
create function public.save_company_allowance_identity_slot(p_company_id uuid,p_slot integer,p_expected_version bigint,p_name text,p_unit text,p_amount_yen integer,p_confirmed boolean) returns jsonb
language sql security invoker set search_path='' as $$select company_allowance_identity_private.edit_slot(p_company_id,p_slot,p_expected_version,p_name,p_unit,p_amount_yen,p_confirmed)$$;
revoke all on function public.read_company_allowance_identity_admin(uuid),public.adopt_company_allowance_identity(uuid,jsonb,boolean),public.read_company_allowance_identity_labels(uuid),public.save_company_allowance_identity_slot(uuid,integer,bigint,text,text,integer,boolean) from public,anon;
grant execute on function public.read_company_allowance_identity_admin(uuid),public.adopt_company_allowance_identity(uuid,jsonb,boolean),public.read_company_allowance_identity_labels(uuid),public.save_company_allowance_identity_slot(uuid,integer,bigint,text,text,integer,boolean) to authenticated;
