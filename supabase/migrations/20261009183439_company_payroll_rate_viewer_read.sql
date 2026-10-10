-- Source-only viewer read adoption; rate writes and raw grants stay unchanged.
DO $$ BEGIN
 if not exists(select 1 from pg_proc where oid=to_regprocedure('payroll_rate_private.read_rates(uuid)') and md5(prosrc)='dac548c55bf3cfbf297a744b7ce88950' and prosecdef and proconfig=ARRAY['search_path=""']) then raise exception 'company rate reader prerequisite differs: read_rates(uuid)';end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('payroll_rate_private.require_admin(uuid)') and md5(prosrc)='44dec567b8004fc4fe614aff9a3113a5' and prosecdef and proconfig=ARRAY['search_path=""']) then raise exception 'company rate reader prerequisite differs: require_admin(uuid)';end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('payroll_rate_private.save_scope(uuid,bigint,jsonb,boolean)') and md5(prosrc)='4a89613714197b3bd2a710316c32a778' and prosecdef and proconfig=ARRAY['search_path=""']) then raise exception 'company rate reader prerequisite differs: save_scope(uuid,bigint,jsonb,boolean)';end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('payroll_rate_private.write_rate(uuid,text,bigint,jsonb,boolean,uuid)') and md5(prosrc)='5fad188fb833ad9f75e27181a354ff10' and prosecdef and proconfig=ARRAY['search_path=""']) then raise exception 'company rate reader prerequisite differs: write_rate(uuid,text,bigint,jsonb,boolean,uuid)';end if;
END $$;
create function payroll_rate_private.require_reader(p_company_id uuid) returns boolean
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or private.account_access_allowed() is distinct from true or not exists(
  select 1 from public.company_members cm where cm.company_id=p_company_id and cm.user_id=auth.uid() and cm.role::text in ('owner','admin','viewer')
 ) then raise exception 'payroll rate reader access denied' using errcode='42501';end if;
 perform 1 from public.companies where id=p_company_id for key share;
 if not found then raise exception 'payroll rate reader access denied' using errcode='42501';end if;
 -- Capability is returned from actual membership, never a client role fallback.
 return exists(select 1 from public.company_members cm where cm.company_id=p_company_id and cm.user_id=auth.uid() and cm.role::text in ('owner','admin'));
end$$;
revoke all on function payroll_rate_private.require_reader(uuid) from public,anon,authenticated;
create or replace function payroll_rate_private.read_rates(p_company_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare can_edit boolean; v_items jsonb; v_candidates jsonb; v_history jsonb; v_scope jsonb; v_scope_history jsonb;
begin
 can_edit:=payroll_rate_private.require_reader(p_company_id);
 select coalesce(jsonb_agg(jsonb_build_object('item_id',s.item_id,'version',s.version,'value',s.value,'origin',s.origin) order by s.item_id),'[]'::jsonb)
 into v_items from payroll_rate_private.settings s where s.company_id=p_company_id;
 select coalesce(jsonb_agg(jsonb_build_object('candidate_id',c.candidate_id,'item_id',c.item_id,'value',c.value,'checked_at',c.checked_at,'scope_version',c.scope_version) order by c.checked_at desc),'[]'::jsonb)
 into v_candidates from (
  select distinct on (candidate.item_id) candidate.* from payroll_rate_private.candidates candidate
  where candidate.company_id=p_company_id
  order by candidate.item_id,candidate.checked_at desc,candidate.candidate_id desc
 ) c;
 if can_edit then
 select coalesce(jsonb_agg(to_jsonb(h) - 'company_id' order by h.changed_at desc,h.version desc),'[]'::jsonb)
 into v_history from payroll_rate_private.history h where h.company_id=p_company_id;
 select coalesce(jsonb_agg(to_jsonb(h) - 'company_id' order by h.version desc),'[]'::jsonb)
 into v_scope_history from payroll_rate_private.scope_history h where h.company_id=p_company_id;
 else
  v_history:='[]'::jsonb;v_scope_history:='[]'::jsonb;
 end if;
 select case when can_edit then to_jsonb(s)-'company_id' else to_jsonb(s)-'company_id'-'updated_by' end into v_scope from payroll_rate_private.company_scope s where s.company_id=p_company_id;
 return jsonb_build_object('items',v_items,'candidates',v_candidates,'history',v_history,
  'company_scope',v_scope,'scope_history',v_scope_history,'can_edit',can_edit);
end $$;

