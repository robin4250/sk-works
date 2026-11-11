#!/usr/bin/env bash
set -euo pipefail
cd docs/review/payroll-saved-unit/sql
psql -v ON_ERROR_STOP=1 -h localhost -U postgres -d postgres <<'SQL'
create schema private;
create table public.attendance_entries(id integer);
create table public.daily_report_workers(id integer);
create table public.daily_reports(id integer);
create table public.invoice_detail_lines(id integer);
create table public.invoices(id integer);
create table public.payroll_statements(id integer);
create table public.site_calculation_source_preferences(id integer);
create table public.worker_payroll_settings(id integer);
insert into public.payroll_statements values (42);
SQL
psql -v ON_ERROR_STOP=1 -h localhost -U postgres -d postgres -f source-before.sql
psql -v ON_ERROR_STOP=1 -h localhost -U postgres -d postgres -c 'revoke all on function private.sync_payroll_attendance_detail(uuid,uuid,date) from public;'
meta=$(psql -At -h localhost -U postgres -d postgres -c "select md5((to_jsonb(p)-'prosrc')::text) from pg_proc p where oid=to_regprocedure('private.sync_payroll_attendance_detail(uuid,uuid,date)')")
for f in root-install root-restore; do sed "s/6718ecf80b9d977aaf0748aef5666743/$meta/g" "$f.guarded.sql.review-only" > "/tmp/$f.sql"; done
psql -v ON_ERROR_STOP=1 -h localhost -U postgres -d postgres -f /tmp/root-install.sql
if psql -v ON_ERROR_STOP=1 -h localhost -U postgres -d postgres -f /tmp/root-install.sql; then echo 'repeated install was not rejected' >&2; exit 1; fi
psql -v ON_ERROR_STOP=1 -h localhost -U postgres -d postgres -f /tmp/root-restore.sql
if psql -v ON_ERROR_STOP=1 -h localhost -U postgres -d postgres -f /tmp/root-restore.sql; then echo 'repeated restore was not rejected' >&2; exit 1; fi
test "$(psql -At -h localhost -U postgres -d postgres -c 'select id from public.payroll_statements')" = 42
