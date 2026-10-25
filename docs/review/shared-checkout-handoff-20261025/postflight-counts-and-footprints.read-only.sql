-- READ ONLY only after every listed new namespace/table exists.
-- Compare exact final Native-derived routine footprints, not just these counts.
begin read only;
set local statement_timeout='10s';
set local lock_timeout='2s';
select jsonb_build_object('phase','shared_checkout_off_postflight','application_data_mutations',false,
 'new_table_counts',jsonb_build_object(
 'checkout_paid_hours_candidate_private.drafts',(select count(*) from checkout_paid_hours_candidate_private.drafts),
 'checkout_paid_hours_candidate_private.ledger',(select count(*) from checkout_paid_hours_candidate_private.ledger),
 'checkout_shared_hours_private.approved_fact_copies',(select count(*) from checkout_shared_hours_private.approved_fact_copies),
 'checkout_shared_hours_private.confirmations',(select count(*) from checkout_shared_hours_private.confirmations),
 'checkout_shared_hours_private.ledger',(select count(*) from checkout_shared_hours_private.ledger),
 'checkout_shared_hours_private.materialization_permits',(select count(*) from checkout_shared_hours_private.materialization_permits),
 'checkout_shared_hours_private.rollout',(select count(*) from checkout_shared_hours_private.rollout),
 'checkout_shared_hours_private.supervisor_contexts',(select count(*) from checkout_shared_hours_private.supervisor_contexts),
 'checkout_shared_hours_private.work_protocol',(select count(*) from checkout_shared_hours_private.work_protocol),
 'checkout_shared_managed_private.adoption_events',(select count(*) from checkout_shared_managed_private.adoption_events),
 'checkout_shared_managed_private.adoptions',(select count(*) from checkout_shared_managed_private.adoptions),
 'checkout_shared_managed_private.manager_receipts',(select count(*) from checkout_shared_managed_private.manager_receipts),
 'scheduled_checkout_private.postponements',(select count(*) from scheduled_checkout_private.postponements),
 'scheduled_checkout_private.rollout',(select count(*) from scheduled_checkout_private.rollout),
 'scheduled_checkout_private.settings',(select count(*) from scheduled_checkout_private.settings),
 'scheduled_checkout_private.sources',(select count(*) from scheduled_checkout_private.sources),
 'shared_daily_report_private.clock_group_context',(select count(*) from shared_daily_report_private.clock_group_context),
 'shared_daily_report_private.rollout',(select count(*) from shared_daily_report_private.rollout),
 'shared_daily_report_private.signature_events',(select count(*) from shared_daily_report_private.signature_events),
 'shared_daily_report_private.work_protocol',(select count(*) from shared_daily_report_private.work_protocol),
 'shared_report_edit_private.sessions',(select count(*) from shared_report_edit_private.sessions)),
 'routines',(select jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'source_md5',md5(p.prosrc),
  'owner',pg_get_userbyid(p.proowner),'secdef',p.prosecdef,'volatility',p.provolatile,'configuration',p.proconfig,'acl',p.proacl::text)
  order by p.oid::regprocedure::text) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname in('checkout_paid_hours_candidate_private','checkout_shared_hours_private','checkout_shared_managed_private','scheduled_checkout_private','shared_daily_report_private','shared_report_edit_private','shared_worker_facts_private')),
 'public_routines',(select jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'source_md5',md5(p.prosrc),
 'owner',pg_get_userbyid(p.proowner),'secdef',p.prosecdef,'configuration',p.proconfig,'acl',p.proacl::text)
 order by p.oid::regprocedure::text) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'
 and p.proname in('collect_approved_shared_report_supervisor_signature','collect_shared_report_supervisor_signature','confirm_managed_shared_work_hours','confirm_managed_shared_worker_facts','confirm_shared_worker_facts','disable_my_gps_work_schedule','manage_shared_report_signature','manage_shared_report_supervisor_signature','postpone_my_scheduled_checkout','read_checkout_paid_work_hours','read_my_gps_work_schedule','read_my_scheduled_checkout','read_my_scheduled_checkout_notification_plan','read_my_shared_daily_report','read_shared_daily_report_context','read_shared_worker_facts','reuse_my_shared_daily_report','save_checkout_paid_work_hours','save_my_gps_work_schedule','submit_shared_daily_report')),
 'private_sequence_privileges',(select coalesce(jsonb_agg(jsonb_build_object('sequence',c.oid::regclass::text,
 'acl',c.relacl::text,'anon_usage',has_sequence_privilege('anon',c.oid,'usage'),'auth_usage',has_sequence_privilege('authenticated',c.oid,'usage'),
 'service_usage',has_sequence_privilege('service_role',c.oid,'usage')) order by c.oid::regclass::text),'[]')
 from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.relkind='S' and n.nspname in('checkout_paid_hours_candidate_private','checkout_shared_hours_private','checkout_shared_managed_private','scheduled_checkout_private','shared_daily_report_private','shared_report_edit_private','shared_worker_facts_private')),
 'private_table_privileges',(select coalesce(jsonb_agg(jsonb_build_object('table',c.oid::regclass::text,'rls',c.relrowsecurity,
 'acl',c.relacl::text,'anon_select',has_table_privilege('anon',c.oid,'select'),'auth_select',has_table_privilege('authenticated',c.oid,'select'),
 'service_select',has_table_privilege('service_role',c.oid,'select')) order by c.oid::regclass::text),'[]')
 from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.relkind in('r','p') and n.nspname in('checkout_paid_hours_candidate_private','checkout_shared_hours_private','checkout_shared_managed_private','scheduled_checkout_private','shared_daily_report_private','shared_report_edit_private','shared_worker_facts_private'))
) as result;
commit;
