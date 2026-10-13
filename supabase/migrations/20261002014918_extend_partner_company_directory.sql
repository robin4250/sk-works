alter table public.partner_companies
  add column if not exists postal_code text,
  add column if not exists fax text,
  add column if not exists president_name text,
  add column if not exists president_mobile text,
  add column if not exists president_home_area text;

update public.partner_companies
set president_name=contact_name
where president_name is null
  and nullif(trim(contact_name),'') is not null;
