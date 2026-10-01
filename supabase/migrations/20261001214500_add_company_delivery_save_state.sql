create table if not exists private.company_delivery_saved_items (
  company_id uuid not null references public.companies(id) on delete cascade,
  item_key text not null,
  saved_by uuid not null,
  saved_at timestamptz not null default now(),
  primary key(company_id,item_key),
  check (length(item_key) between 6 and 80)
);

alter table private.company_delivery_saved_items enable row level security;

create or replace function private.company_delivery_saved_keys()
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare c uuid;
begin
  select m.company_id into c
  from public.company_members m
  where m.user_id=auth.uid() and m.role::text in ('owner','admin')
  limit 1;
  if c is null then raise exception '会社の管理者だけが操作できます。'; end if;

  return coalesce((
    select jsonb_agg(s.item_key order by s.saved_at desc)
    from private.company_delivery_saved_items s
    where s.company_id=c
  ), '[]'::jsonb);
end
$$;

create or replace function private.save_company_delivery_items(
  p_item_keys text[]
)
returns void
language plpgsql
security definer
set search_path=''
as $$
declare
  c uuid;
  k text;
  item_id uuid;
  item_kind text;
begin
  select m.company_id into c
  from public.company_members m
  where m.user_id=auth.uid() and m.role::text in ('owner','admin')
  limit 1;
  if c is null then raise exception '会社の管理者だけが操作できます。'; end if;
  if p_item_keys is null or cardinality(p_item_keys) not between 1 and 500 then
    raise exception '保存対象を確認してください。';
  end if;

  foreach k in array p_item_keys loop
    item_kind:=split_part(k,':',1);
    begin
      item_id:=split_part(k,':',2)::uuid;
    exception when others then
      raise exception '保存対象を確認してください。';
    end;

    if item_kind='file' then
      if not exists(
        select 1
        from private.document_delivery_items i
        join private.document_deliveries d on d.id=i.delivery_id
        where i.id=item_id and d.recipient_company_id=c
      ) then
        raise exception '保存できない書類が含まれています。';
      end if;
    elsif item_kind='data' then
      if not exists(
        select 1
        from private.company_data_delivery_items i
        join private.document_deliveries d on d.id=i.delivery_id
        where i.id=item_id and d.recipient_company_id=c
      ) then
        raise exception '保存できないデータが含まれています。';
      end if;
    else
      raise exception '保存対象の種類を確認してください。';
    end if;

    insert into private.company_delivery_saved_items(
      company_id,item_key,saved_by,saved_at
    )
    values(c,k,auth.uid(),now())
    on conflict(company_id,item_key)
    do update set saved_by=excluded.saved_by,saved_at=excluded.saved_at;
  end loop;
end
$$;

create or replace function public.company_delivery_saved_keys()
returns jsonb
language sql
set search_path=''
as $$ select private.company_delivery_saved_keys() $$;

create or replace function public.save_company_delivery_items(
  p_item_keys text[]
)
returns void
language sql
set search_path=''
as $$ select private.save_company_delivery_items(p_item_keys) $$;

revoke all on function public.company_delivery_saved_keys() from public,anon;
revoke all on function public.save_company_delivery_items(text[]) from public,anon;
grant execute on function public.company_delivery_saved_keys() to authenticated;
grant execute on function public.save_company_delivery_items(text[]) to authenticated;
