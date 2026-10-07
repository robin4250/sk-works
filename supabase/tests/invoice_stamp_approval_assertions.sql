select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
insert into public.invoices(id,company_id,billing_period_start,billing_period_end,status,grand_total)
values('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','2026-09-01','2026-09-30','draft',100);
do $$declare first_time timestamptz; n int; begin
 if not public.approve_invoice('20000000-0000-0000-0000-000000000001') then raise exception 'single approval must finalize'; end if;
 select approved_at into first_time from public.invoice_approvals;
 perform public.approve_invoice('20000000-0000-0000-0000-000000000001');
 if (select count(*) from public.invoice_approval_audit where action='approved')<>1 then raise exception 'duplicate audit'; end if;
 perform public.set_invoice_stamp_date_policy('closing');
 if (select display_date from public.invoice_approval_status_rows_v2('20000000-0000-0000-0000-000000000001'))<>'2026-09-30'::date then raise exception 'closing date'; end if;
 perform public.set_invoice_stamp_display_date('20000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','2026-09-29');
 if (select approved_at from public.invoice_approvals)<>first_time then raise exception 'actual time changed'; end if;
 if (select display_date from public.invoice_approval_status_rows_v2('20000000-0000-0000-0000-000000000001'))<>'2026-09-29'::date then raise exception 'override date'; end if;
 perform public.cancel_invoice_approval('20000000-0000-0000-0000-000000000001');
 if (select approval_finalized_at from public.invoices) is not null then raise exception 'cancel final'; end if;
 perform public.approve_invoice('20000000-0000-0000-0000-000000000001');
 update public.invoices set grand_total=200;
 if exists(select 1 from public.invoice_approvals where status='approved') then raise exception 'invoice material invalidation'; end if;
 perform public.set_invoice_approvers(array['00000000-0000-0000-0000-000000000001'::uuid,'00000000-0000-0000-0000-000000000002'::uuid,'00000000-0000-0000-0000-000000000003'::uuid]);
 if (select count(*) from public.invoice_approvals)<>3 then raise exception 'three approvers'; end if;
 if public.approve_invoice('20000000-0000-0000-0000-000000000001') then raise exception 'premature final'; end if;
 if (select stamp_role from public.invoice_approval_status_rows_v2('20000000-0000-0000-0000-000000000001') where position=1)<>'confirmation' then raise exception 'confirmation role'; end if;
 -- No-op configuration must retain an existing approval.
 perform public.set_invoice_approvers(array['00000000-0000-0000-0000-000000000001'::uuid,'00000000-0000-0000-0000-000000000002'::uuid,'00000000-0000-0000-0000-000000000003'::uuid]);
 if not exists(select 1 from public.invoice_approvals where status='approved') then raise exception 'no-op reset'; end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
select public.approve_invoice('20000000-0000-0000-0000-000000000001');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',false);
do $$begin
 if not public.approve_invoice('20000000-0000-0000-0000-000000000001') then raise exception 'three final'; end if;
 insert into public.invoice_site_calculations values('30000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001',100);
 if exists(select 1 from public.invoice_approvals where status='approved') then raise exception 'calculation invalidation'; end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000004',false);
do $$begin
 begin perform public.approve_invoice('20000000-0000-0000-0000-000000000001'); raise exception 'cross company allowed';
 exception when others then if sqlerrm<>'invoice not found' then raise; end if; end;
 begin perform public.invoice_approval_history('20000000-0000-0000-0000-000000000001'); raise exception 'history leaked';
 exception when others then if sqlerrm<>'invoice not found' then raise; end if; end;
 if has_function_privilege('anon','public.cancel_invoice_approval(uuid)','EXECUTE') then raise exception 'anonymous callable'; end if;
end $$;

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
select public.approve_invoice('20000000-0000-0000-0000-000000000001');
select public.set_invoice_stamp_date_policy('none');
do $$begin
 if (select display_date from public.invoice_approval_status_rows_v2('20000000-0000-0000-0000-000000000001') where position=1) is not null then raise exception 'none date'; end if;
 insert into public.invoice_detail_lines values('60000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001',50);
 if exists(select 1 from public.invoice_approvals where status='approved') then raise exception 'line invalidation'; end if;
end $$;
