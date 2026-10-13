-- Mirrors production migration 20261004134247.
create or replace function private.sync_trade_company_directory()
returns void
language plpgsql
security definer
set search_path=''
as $$
declare
  cid uuid;
  r record;
  existing_id uuid;
begin
  cid:=private.current_company_admin_id();
  if cid is null then raise exception '管理者のみ操作できます。'; end if;

  for r in
    select c.id,c.name,c.billing_address
    from public.customers c
    where c.company_id=cid
  loop
    select tc.id into existing_id
    from public.trade_companies tc
    where tc.company_id=cid
      and (tc.customer_id=r.id or lower(trim(tc.name))=lower(trim(r.name)))
    order by (tc.customer_id=r.id) desc,tc.created_at
    limit 1;

    if existing_id is null then
      insert into public.trade_companies(
        company_id,name,address,trade_role,customer_id,created_by,updated_by
      )
      values(cid,r.name,r.billing_address,'customer',r.id,auth.uid(),auth.uid());
    else
      update public.trade_companies
      set customer_id=coalesce(customer_id,r.id),
          trade_role=case when trade_role='subcontractor' then 'both' else trade_role end,
          updated_at=now()
      where id=existing_id;
    end if;
  end loop;

  for r in
    select p.id,p.name,p.postal_code,p.address,p.phone,p.email
    from public.partner_companies p
    where p.company_id=cid
  loop
    select tc.id into existing_id
    from public.trade_companies tc
    where tc.company_id=cid
      and (tc.partner_company_id=r.id or lower(trim(tc.name))=lower(trim(r.name)))
    order by (tc.partner_company_id=r.id) desc,tc.created_at
    limit 1;

    if existing_id is null then
      insert into public.trade_companies(
        company_id,name,postal_code,address,phone,email,trade_role,
        partner_company_id,created_by,updated_by
      )
      values(
        cid,r.name,r.postal_code,r.address,r.phone,r.email,'subcontractor',
        r.id,auth.uid(),auth.uid()
      );
    else
      update public.trade_companies
      set partner_company_id=coalesce(partner_company_id,r.id),
          postal_code=coalesce(nullif(postal_code,''),r.postal_code),
          address=coalesce(nullif(address,''),r.address),
          phone=coalesce(nullif(phone,''),r.phone),
          email=coalesce(nullif(email,''),r.email),
          trade_role=case when trade_role='customer' then 'both' else trade_role end,
          updated_at=now()
      where id=existing_id;
    end if;
  end loop;

  for r in
    select cc.parent_company_id as linked_id,co.name,co.postal_code,co.address,
           co.phone,co.email,co.corporate_number,'customer'::text as role_name
    from private.company_connections cc
    join public.companies co on co.id=cc.parent_company_id
    where cc.child_company_id=cid and cc.status='accepted'
    union all
    select cc.child_company_id as linked_id,co.name,co.postal_code,co.address,
           co.phone,co.email,co.corporate_number,'subcontractor'::text as role_name
    from private.company_connections cc
    join public.companies co on co.id=cc.child_company_id
    where cc.parent_company_id=cid and cc.status='accepted'
  loop
    select tc.id into existing_id
    from public.trade_companies tc
    where tc.company_id=cid
      and (
        tc.linked_company_id=r.linked_id
        or (
          tc.linked_company_id is null
          and lower(trim(tc.name))=lower(trim(r.name))
        )
      )
    order by (tc.linked_company_id=r.linked_id) desc,tc.created_at
    limit 1;

    if existing_id is null then
      insert into public.trade_companies(
        company_id,name,postal_code,address,phone,email,corporate_number,
        trade_role,linked_company_id,link_status,created_by,updated_by
      )
      values(
        cid,r.name,r.postal_code,r.address,r.phone,r.email,r.corporate_number,
        r.role_name,r.linked_id,'linked',auth.uid(),auth.uid()
      );
    else
      update public.trade_companies
      set linked_company_id=r.linked_id,
          link_status='linked',
          postal_code=coalesce(nullif(postal_code,''),r.postal_code),
          address=coalesce(nullif(address,''),r.address),
          phone=coalesce(nullif(phone,''),r.phone),
          email=coalesce(nullif(email,''),r.email),
          corporate_number=coalesce(nullif(corporate_number,''),r.corporate_number),
          trade_role=case
            when trade_role<>r.role_name and trade_role<>'both' then 'both'
            else trade_role
          end,
          updated_at=now()
      where id=existing_id;
    end if;
  end loop;
end
$$;

revoke all on function private.sync_trade_company_directory()
from public,anon,authenticated;

create or replace function public.sync_trade_company_directory()
returns void
language sql
set search_path=''
as $$ select private.sync_trade_company_directory() $$;

revoke all on function public.sync_trade_company_directory()
from public,anon;
grant execute on function public.sync_trade_company_directory()
to authenticated;

insert into public.trade_companies(
  company_id,name,address,trade_role,customer_id
)
select c.company_id,c.name,c.billing_address,'customer',c.id
from public.customers c
where not exists(
  select 1 from public.trade_companies tc
  where tc.company_id=c.company_id
    and (tc.customer_id=c.id or lower(trim(tc.name))=lower(trim(c.name)))
);

update public.trade_companies tc
set customer_id=c.id,
    trade_role=case when tc.trade_role='subcontractor' then 'both' else tc.trade_role end,
    updated_at=now()
from public.customers c
where tc.company_id=c.company_id
  and tc.customer_id is null
  and lower(trim(tc.name))=lower(trim(c.name));

insert into public.trade_companies(
  company_id,name,postal_code,address,phone,email,trade_role,partner_company_id
)
select p.company_id,p.name,p.postal_code,p.address,p.phone,p.email,'subcontractor',p.id
from public.partner_companies p
where not exists(
  select 1 from public.trade_companies tc
  where tc.company_id=p.company_id
    and (tc.partner_company_id=p.id or lower(trim(tc.name))=lower(trim(p.name)))
);

update public.trade_companies tc
set partner_company_id=p.id,
    postal_code=coalesce(nullif(tc.postal_code,''),p.postal_code),
    address=coalesce(nullif(tc.address,''),p.address),
    phone=coalesce(nullif(tc.phone,''),p.phone),
    email=coalesce(nullif(tc.email,''),p.email),
    trade_role=case when tc.trade_role='customer' then 'both' else tc.trade_role end,
    updated_at=now()
from public.partner_companies p
where tc.company_id=p.company_id
  and tc.partner_company_id is null
  and lower(trim(tc.name))=lower(trim(p.name));

insert into public.trade_companies(
  company_id,name,postal_code,address,phone,email,corporate_number,
  trade_role,linked_company_id,link_status
)
select cc.child_company_id,co.name,co.postal_code,co.address,co.phone,co.email,
       co.corporate_number,'customer',co.id,'linked'
from private.company_connections cc
join public.companies co on co.id=cc.parent_company_id
where cc.status='accepted'
  and not exists(
    select 1 from public.trade_companies tc
    where tc.company_id=cc.child_company_id
      and tc.linked_company_id=co.id
  );

insert into public.trade_companies(
  company_id,name,postal_code,address,phone,email,corporate_number,
  trade_role,linked_company_id,link_status
)
select cc.parent_company_id,co.name,co.postal_code,co.address,co.phone,co.email,
       co.corporate_number,'subcontractor',co.id,'linked'
from private.company_connections cc
join public.companies co on co.id=cc.child_company_id
where cc.status='accepted'
  and not exists(
    select 1 from public.trade_companies tc
    where tc.company_id=cc.parent_company_id
      and tc.linked_company_id=co.id
  );
