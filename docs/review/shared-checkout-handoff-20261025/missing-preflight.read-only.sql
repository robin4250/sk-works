-- READ ONLY preparation query. No Auth rows/credentials or app values.
-- Captures exact original definitions for bounded rollback and source review.
begin read only;
set local statement_timeout='10s';
set local lock_timeout='2s';
with expected(signature,source_md5) as (values
 ('company_checkout_allowance_private.aggregate(jsonb)','18f0e5b15f40e6281d6c3d90ffa5b6d3'),
 ('company_checkout_allowance_private.report_basis(uuid)','d9d5e378f6ab76d7f6f6a6be487abd10'),
 ('company_checkout_allowance_private.resolve(uuid,uuid,date,date)','c1f9bf82b91b1b430ca1b7e951af60cc'),
 ('private.save_daily_report_signature(uuid,text,text,jsonb)','40f29d53008e6bf5610ce25e5fa96ef3'),
 ('public.sign_daily_report(uuid,text,jsonb)','a433ab29499da6e50ba930a5d3243957'),
 ('payroll_scope_private.lock_scopes(jsonb,boolean)','1bce36e2e59eeb8e0144c5743b8ea800'),
 ('private.validate_attendance_shift_evidence()','e1d6e6a1b8da732d8bcf5f55d3f1374b'),
 ('private.route_journey_visit_before_clock_out()','7d52106e169225a400e5fef63841e7a8'),
 ('private.account_access_allowed()','aeca25db212c043c472334026bd98724'),
 ('checkout_report_registration_private.current_actor()','9ca270fa06ff48883705cea5d18a8f2f'),
 ('private.save_daily_report_vehicle_usage(uuid,uuid,uuid,uuid,numeric)','f78e35bf948cc4702f9d65d28d0ac0e6'),
 ('private.enqueue_notification(uuid,uuid,text,text,text,text,uuid)','260ef8dc60ec1917cc0c8dc85ea52872'),
 ('public.save_daily_report_destination_draft(uuid,uuid,uuid,date,text,jsonb)','8c341bb00650cab35b1fa23b34e69eae'),
 ('company_checkout_allowance_private.normalize_choices(uuid,uuid,jsonb)','fc194da8e58428711eb7632eb83d959b'),
 ('company_checkout_allowance_private.validate_labels(uuid,uuid,text,jsonb,text)','8499555a09c3f4ecfe9d406a1eb8c2ad'),
 ('public.force_manage_attendance(text,jsonb)','077b4a1373689071c84e0a14f0a8d824')
), ns(name) as(values ('checkout_paid_hours_candidate_private'),('checkout_shared_hours_private'),('checkout_shared_managed_private'),('scheduled_checkout_private'),('shared_daily_report_private'),('shared_report_edit_private'),('shared_worker_facts_private')), rpc(name) as(values ('collect_approved_shared_report_supervisor_signature'),('collect_shared_report_supervisor_signature'),('confirm_managed_shared_work_hours'),('confirm_managed_shared_worker_facts'),('confirm_shared_worker_facts'),('disable_my_gps_work_schedule'),('manage_shared_report_signature'),('manage_shared_report_supervisor_signature'),('postpone_my_scheduled_checkout'),('read_checkout_paid_work_hours'),('read_my_gps_work_schedule'),('read_my_scheduled_checkout'),('read_my_scheduled_checkout_notification_plan'),('read_my_shared_daily_report'),('read_shared_daily_report_context'),('read_shared_worker_facts'),('reuse_my_shared_daily_report'),('save_checkout_paid_work_hours'),('save_my_gps_work_schedule'),('submit_shared_daily_report')),
metadata as(select e.signature,e.source_md5 expected_md5,p.oid is not null present,
 md5(p.prosrc) observed_md5,pg_get_userbyid(p.proowner) owner,p.prosecdef,
 p.provolatile,p.proconfig,p.proacl::text acl,pg_get_functiondef(p.oid) definition,
 p.oid is not null and md5(p.prosrc)=e.source_md5 source_matches
 from expected e left join pg_proc p on p.oid=to_regprocedure(e.signature))
select jsonb_build_object('schema',1,'phase','shared_checkout_missing_preflight',
 'application_data_mutations',false,'role',current_user,
 'functions',(select jsonb_agg(to_jsonb(m) order by signature) from metadata m),
 'all_source_pins_match',(select bool_and(source_matches) from metadata),
 'new_namespaces',(select jsonb_agg(jsonb_build_object('schema',name,'absent',to_regnamespace(name) is null) order by name) from ns),
 'colliding_public_rpc_names',(select coalesce(jsonb_agg(p.oid::regprocedure::text order by p.oid::regprocedure::text),'[]')
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in(select name from rpc)),
 'existing_av_ae_report_triggers',(select jsonb_agg(jsonb_build_object('table',t.tgrelid::regclass::text,'name',t.tgname,
 'type',t.tgtype,'enabled',t.tgenabled,'definition',pg_get_triggerdef(t.oid,true),'function',p.oid::regprocedure::text,
 'source_md5',md5(p.prosrc),'owner',pg_get_userbyid(p.proowner),'secdef',p.prosecdef,'config',p.proconfig,'acl',p.proacl::text)
 order by t.tgrelid::regclass::text,t.tgname) from pg_trigger t join pg_proc p on p.oid=t.tgfoid
 where not t.tgisinternal and t.tgrelid in('public.attendance_verifications'::regclass,'public.attendance_entries'::regclass,
 'public.daily_reports'::regclass,'public.daily_report_workers'::regclass,'public.daily_report_edit_requests'::regclass)),
 'function_default_acls',(select coalesce(jsonb_agg(jsonb_build_object('owner',pg_get_userbyid(d.defaclrole),'schema',n.nspname,'acl',d.defaclacl::text)),'[]')
 from pg_default_acl d left join pg_namespace n on n.oid=d.defaclnamespace where d.defaclobjtype='f' and d.defaclrole=(select oid from pg_roles where rolname='postgres')),
 'required_schedule_routines',(select jsonb_agg(jsonb_build_object('signature',sig,'present',to_regprocedure(sig) is not null))
 from (values ('public.save_my_attendance_selection(text,uuid,smallint[],time without time zone,text)'),
 ('public.save_my_route_attendance_selection(text,uuid,smallint[],time without time zone,text)')) x(sig)),
 'required_schedule_tables',(select jsonb_agg(jsonb_build_object('table',name,'present',to_regclass(name) is not null))
 from (values('public.gps_auto_attendance_schedules'),('public.work_attendance_selections'),('public.work_vehicle_route_selections')) x(name))
) as result;
commit;
