-- Separate configuration only: never changes source messages, drafts or invoices.
create table private.line_reading_rules (
 group_id uuid primary key references public.communication_groups(id),
 revision integer not null default 1,
 rules jsonb not null default '[]'::jsonb,
 updated_by uuid not null references auth.users(id),
 updated_at timestamptz not null default now()
);
alter table private.line_reading_rules enable row level security;
revoke all on private.line_reading_rules from public,anon,authenticated;

create function private.line_reading_rules_workspace(p_group_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare access jsonb; record private.line_reading_rules;
begin
 if auth.uid() is null or public.is_current_user_master_admin() is distinct from true then
  raise exception 'master reading rules access required' using errcode='42501';
 end if;
 access:=private.line_import_access(p_group_id,'invoice');
 select * into record from private.line_reading_rules where group_id=p_group_id;
 return jsonb_build_object('revision',coalesce(record.revision,0),'rules',coalesce(record.rules,'[]'::jsonb),'can_edit',access->'can_edit');
end $$;

create function private.save_line_reading_rules(p_group_id uuid,p_expected_revision integer,p_rules jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare access jsonb; rule jsonb; revision integer;
begin
 if auth.uid() is null or public.is_current_user_master_admin() is distinct from true then
  raise exception 'master reading rules access required' using errcode='42501';
 end if;
 access:=private.line_import_access(p_group_id,'invoice');
 if not (access->>'can_edit')::boolean then raise exception 'rules edit denied' using errcode='42501';end if;
 if p_rules is null or jsonb_typeof(p_rules)<>'array' or jsonb_array_length(p_rules)>1000 then raise exception 'invalid rules';end if;
 for rule in select value from jsonb_array_elements(p_rules) loop
  if jsonb_typeof(rule)<>'object' or jsonb_typeof(rule->'phrase') is distinct from 'string' or jsonb_typeof(rule->'value') is distinct from 'string'
   or length(trim(rule->>'phrase')) not between 1 and 80 or length(trim(rule->>'value')) not between 1 and 80
   or coalesce(rule->>'kind','') not in ('site','worker','allowance','workCategory','overtime','early','ignore') then raise exception 'invalid rule';end if;
 end loop;
 if exists(select 1 from jsonb_array_elements(p_rules) r group by r->>'phrase' having count(*)>1) then raise exception 'duplicate phrase';end if;
 -- Serialize first-insert as well as updates without granting table access.
 perform pg_advisory_xact_lock(hashtextextended(p_group_id::text,1729));
 select r.revision into revision from private.line_reading_rules r where group_id=p_group_id for update;
 if p_expected_revision is null or coalesce(revision,0)<>p_expected_revision then raise exception 'rules changed; reload' using errcode='40001';end if;
 insert into private.line_reading_rules(group_id,revision,rules,updated_by) values(p_group_id,1,p_rules,auth.uid())
 on conflict(group_id) do update set revision=private.line_reading_rules.revision+1,rules=excluded.rules,updated_by=auth.uid(),updated_at=now();
 return private.line_reading_rules_workspace(p_group_id);
end $$;
create function public.line_reading_rules_workspace(p_group_id uuid) returns jsonb language sql security invoker set search_path='' as $$select private.line_reading_rules_workspace(p_group_id)$$;
create function public.save_line_reading_rules(p_group_id uuid,p_expected_revision integer,p_rules jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.save_line_reading_rules(p_group_id,p_expected_revision,p_rules)$$;
revoke all on function private.line_reading_rules_workspace(uuid),private.save_line_reading_rules(uuid,integer,jsonb),public.line_reading_rules_workspace(uuid),public.save_line_reading_rules(uuid,integer,jsonb) from public,anon;
grant execute on function private.line_reading_rules_workspace(uuid),private.save_line_reading_rules(uuid,integer,jsonb),public.line_reading_rules_workspace(uuid),public.save_line_reading_rules(uuid,integer,jsonb) to authenticated;
