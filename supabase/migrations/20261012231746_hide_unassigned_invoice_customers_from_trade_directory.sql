-- Forward-only exclusion by canonical customer marker; no data deletion or renaming.
-- Preserve function owner, ACL, authorization and search_path through CREATE OR REPLACE.
begin;
set local lock_timeout='5s';
do $trade_filter$
declare definition text; body text;
begin
 select p.prosrc,pg_get_functiondef(p.oid) into body,definition
 from pg_proc p where p.oid='private.sync_trade_company_directory()'::regprocedure;
 if md5(body)<>'0d9c3f7f4bb627cac571a4fb88b1d9cf' then
   raise exception 'Trade directory source changed; review forward migration' using errcode='55000';
 end if;
 if (length(body)-length(replace(body,$old$    where c.company_id=cid
  loop$old$,'')))/length($old$    where c.company_id=cid
  loop$old$)<>1 then
   raise exception 'Trade directory filter boundary changed' using errcode='55000';
 end if;
 execute replace(definition,$old$    where c.company_id=cid
  loop$old$,$new$    where c.company_id=cid
      and c.notes is distinct from 'sko_system_unassigned_invoice_customer'
  loop$new$);
end
$trade_filter$;

do $trade_filter$
declare definition text; body text;
begin
 select p.prosrc,pg_get_functiondef(p.oid) into body,definition
 from pg_proc p where p.oid='private.trade_company_workspace()'::regprocedure;
 if md5(body)<>'b9c2124518a11492ee9baa079fce59fa' then
   raise exception 'Trade directory source changed; review forward migration' using errcode='55000';
 end if;
 if (length(body)-length(replace(body,$old$    where tc.company_id=cid
  ),$old$,'')))/length($old$    where tc.company_id=cid
  ),$old$)<>1 then
   raise exception 'Trade directory filter boundary changed' using errcode='55000';
 end if;
 execute replace(definition,$old$    where tc.company_id=cid
  ),$old$,$new$    where tc.company_id=cid
      and not exists (
        select 1 from public.customers system_customer
        where system_customer.company_id=tc.company_id
          and system_customer.id=tc.customer_id
          and system_customer.notes='sko_system_unassigned_invoice_customer'
      )
  ),$new$);
end
$trade_filter$;
commit;
