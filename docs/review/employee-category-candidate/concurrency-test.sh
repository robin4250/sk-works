#!/usr/bin/env bash
set -euo pipefail
SKO_LOCK_READY=$(mktemp -u)
export SKO_LOCK_READY
cleanup() { rm -f "$SKO_LOCK_READY"; }
trap cleanup EXIT
psql -v ON_ERROR_STOP=1 <<'SQL' &
begin;
select set_config('test.actor','20000000-0000-0000-0000-000000000001',false);
select 1 from public.workers where id='30000000-0000-0000-0000-000000000001' for update;
\! touch "$SKO_LOCK_READY"
select pg_sleep(3);
select private.apply_worker_personnel_payload('30000000-0000-0000-0000-000000000001',jsonb_build_object('employee_category_id',(select id from employee_category_private.categories where name='正社員')),'20000000-0000-0000-0000-000000000001');
commit;
SQL
first=$!
for i in $(seq 1 100); do [ -f "$SKO_LOCK_READY" ] && break; kill -0 "$first"; sleep 0.05; done
[ -f "$SKO_LOCK_READY" ]
psql -v ON_ERROR_STOP=1 <<'SQL'
begin;
select private.apply_worker_personnel_payload('30000000-0000-0000-0000-000000000001',jsonb_build_object('employee_category_id',(select id from employee_category_private.categories where name='アルバイト')),'20000000-0000-0000-0000-000000000001');
commit;
SQL
wait "$first"
psql -v ON_ERROR_STOP=1 <<'SQL'
do $$ declare logs jsonb; begin
 select jsonb_agg(jsonb_build_array(c1.name,c2.name) order by a.id) into logs from employee_category_private.audit a left join employee_category_private.categories c1 on c1.id=a.old_category left join employee_category_private.categories c2 on c2.id=a.new_category where a.id in (select id from employee_category_private.audit where action='assignment_change' order by id desc limit 2);
 assert logs='[["派遣社員","正社員"],["正社員","アルバイト"]]'::jsonb, 'serialized audit transitions wrong';
end $$;
SQL
