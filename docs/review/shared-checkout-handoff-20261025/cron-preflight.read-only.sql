-- READ ONLY; run only when catalog confirms cron.job exists.
begin read only;
set local statement_timeout='5s';
select coalesce(jsonb_agg(jsonb_build_object('jobid',jobid,'jobname',jobname,'schedule',schedule,'command',command,'database',database,'username',username,'active',active) order by jobid),'[]') as matching_jobs
from cron.job
where command ~ '(checkout_report_registration_private|checkout_paid_hours_candidate_private|checkout_shared_hours_private|checkout_shared_managed_private|scheduled_checkout_private|shared_daily_report_private|shared_report_edit_private|shared_worker_facts_private)'
 or jobname='checkout-report-registration-daily';
commit;
