import fs from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
export function buildGuardedApply(contact,visit){
 if(!/^begin;\s/.test(contact)||!contact.trimEnd().endsWith('commit;'))throw Error('unexpected contact transaction wrapper');
 contact=contact.replace(/^begin;\s*/,'').replace(/commit;\s*$/,'');
 return `begin;
set local lock_timeout='5s';
set local statement_timeout='90s';
select pg_advisory_xact_lock(hashtextextended('sko-route-visit-reports-20261011',0));
do $pre$ begin
 if to_regclass('private.route_visit_reports') is not null then raise exception 'visit report objects already exist'; end if;
 if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private') and p.proname in ('route_visit_report_context','route_visit_report_command','read_route_visit_report','choose_route_visit_report','save_route_visit_report_draft','save_route_visit_report_signature')) then raise exception 'visit report functions already exist'; end if;
 if to_regprocedure('private.route_journey_visit_exact(uuid)') is null or to_regprocedure('private.account_access_allowed()') is null then raise exception 'visit dependencies missing'; end if;
end $pre$;
create temp table route_apply_existing_tables as select c.oid,n.nspname,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private') and c.relkind in ('r','p');
do $locks$ declare r record; begin
 for r in select * from route_apply_existing_tables order by oid loop execute format('lock table %I.%I in share mode',r.nspname,r.relname); end loop;
end $locks$;
create function pg_temp.route_apply_snapshot() returns jsonb language plpgsql as $snap$
declare result jsonb; r record; fingerprint text; rows jsonb:='{}';
begin
 for r in select * from route_apply_existing_tables order by oid loop
  execute format('select md5(coalesce(string_agg(md5((to_jsonb(t)-%L::text[])::text),%L order by md5((to_jsonb(t)-%L::text[])::text)),%L)) from %I.%I t',
   case when r.nspname='public' and r.relname='route_assignments' then '{responsible_name,responsible_phone}' else '{}' end,'',
   case when r.nspname='public' and r.relname='route_assignments' then '{responsible_name,responsible_phone}' else '{}' end,'',r.nspname,r.relname) into fingerprint;
  rows:=rows||jsonb_build_object(r.oid::text,fingerprint);
 end loop;
 select jsonb_build_object(
 'functions',(select coalesce(jsonb_object_agg(p.oid::text,to_jsonb(p)),'{}') from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private')),
 'tables',(select coalesce(jsonb_object_agg(c.oid::text,jsonb_build_object('owner',c.relowner,'acl',c.relacl,'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,'kind',c.relkind)),'{}') from pg_class c join route_apply_existing_tables t on t.oid=c.oid),
 'columns',(select coalesce(jsonb_object_agg(a.attrelid::text||':'||a.attnum::text,to_jsonb(a)),'{}') from pg_attribute a join route_apply_existing_tables t on t.oid=a.attrelid where a.attnum>0 and not a.attisdropped and not(t.nspname='public' and t.relname='route_assignments' and a.attname in ('responsible_name','responsible_phone'))),
 'schemas',(select coalesce(jsonb_object_agg(n.oid::text,to_jsonb(n)),'{}') from pg_namespace n where n.nspname in ('public','private')),
 'constraints',(select coalesce(jsonb_object_agg(c.oid::text,to_jsonb(c)),'{}') from pg_constraint c join route_apply_existing_tables t on t.oid=c.conrelid),
 'defaults',(select coalesce(jsonb_object_agg(d.oid::text,to_jsonb(d)),'{}') from pg_attrdef d join route_apply_existing_tables t on t.oid=d.adrelid),
 'policies',(select coalesce(jsonb_object_agg(p.oid::text,to_jsonb(p)),'{}') from pg_policy p join route_apply_existing_tables t on t.oid=p.polrelid),
 'triggers',(select coalesce(jsonb_object_agg(p.oid::text,to_jsonb(p)),'{}') from pg_trigger p join route_apply_existing_tables t on t.oid=p.tgrelid),
 'rows',rows) into result;
 return result;
end $snap$;
create temp table route_apply_before as select pg_temp.route_apply_snapshot() value;
${contact}
${visit}
do $post$ declare before jsonb; after jsonb; k text; begin
 select value into before from route_apply_before; after:=pg_temp.route_apply_snapshot();
 foreach k in array array['functions','tables','columns','policies','triggers','rows','schemas','constraints','defaults'] loop
  if not((after->k) @> (before->k)) then raise exception 'route apply preservation failed: %',k; end if;
 end loop;
 if exists(select 1 from public.route_assignments where responsible_name is not null or responsible_phone is not null) then raise exception 'old route contact data changed'; end if;
 if exists(select 1 from private.route_visit_reports) then raise exception 'unexpected visit backfill'; end if;
end $post$;
drop function pg_temp.route_apply_snapshot();
drop table route_apply_before,route_apply_existing_tables;
commit;
`;
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
 const root=process.argv[2]||new URL('..',import.meta.url).pathname;
 const contact=await fs.readFile(root+'/supabase/migrations/20261011121418_route_responsible_contact.sql','utf8');
 const visit=await fs.readFile(root+'/supabase/migrations/20261011121738_route_visit_report_documents.sql','utf8');
 process.stdout.write(buildGuardedApply(contact,visit));
}
