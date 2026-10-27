-- Scheduler metadata fixture only. No actual Cron worker runs in this database.
create schema cron;
create table cron.job(jobid bigint primary key,jobname text,schedule text,command text,active boolean,database text);
create table cron.job_run_details(runid bigint primary key,jobid bigint,status text,end_time timestamptz);
create function cron.unschedule(text) returns boolean language plpgsql as $$begin
 delete from cron.job where jobname=$1;return found;end$$;
