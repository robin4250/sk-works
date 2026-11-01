import assert from 'node:assert/strict';
import fs from 'node:fs';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';

export const root=new URL('../../../',new URL('./',import.meta.url));
const manifest=JSON.parse(fs.readFileSync(new URL('dependencies.json',import.meta.url)));
export const info={actor:'10000000-0000-0000-0000-000000000001',company:'20000000-0000-0000-0000-000000000001',worker:'30000000-0000-0000-0000-000000000001',master:'40000000-0000-0000-0000-000000000001',qualification:'50000000-0000-0000-0000-000000000001'};
export function validateEnvironment(e){
 assert.equal(e.PGDATABASE,'retirement_fixture');assert.equal(e.PGUSER,'postgres');
 assert.ok(['127.0.0.1','localhost'].includes(e.PGHOST));assert.equal(e.PGPORT,'55442');
 assert.match(e.SKO_QUALIFICATION_FIXTURE_SERVER_ADDR??'',/^(?:127\.0\.0\.1|::1|10\.\d+\.\d+\.\d+|192\.168\.\d+\.\d+|172\.(?:1[6-9]|2\d|3[01])\.\d+\.\d+)$/);
 for(const k of ['DATABASE_URL','SUPABASE_URL','SUPABASE_SERVICE_ROLE_KEY','SERVICE_ROLE_KEY','PGSERVICE','PGSERVICEFILE','PGHOSTADDR','PGOPTIONS'])assert.ok(!e[k],k);
}
export function sql(query){
 const p=spawnSync('psql',['-XAtq','-v','ON_ERROR_STOP=1','-h',process.env.PGHOST,'-p',process.env.PGPORT,'-U','postgres','-d','retirement_fixture'],{input:query,encoding:'utf8',env:process.env,timeout:15000});
 assert.equal(p.status,0,p.stderr);return p.stdout.trim();
}
export function pinned(path,sha,base=root){const b=fs.readFileSync(new URL(path,base));assert.equal(createHash('sha256').update(b).digest('hex'),sha,path);return b.toString();}
export function sourceInputs(){
 const sources={};for(const [path,sha]of Object.entries(manifest.files))sources[path]=pinned(path,sha);
 const previous=new URL('build/retired-qualification-source/',root);
 for(const [path,sha]of Object.entries(manifest.retirement_files))sources[path]=pinned(path,sha,previous);
 return sources;
}
export function selectedPolicy(source,name){
 const start=source.indexOf('create policy '+name+'\n');assert.ok(start>=0,name);
 const end=source.indexOf(';',start);assert.ok(end>start);return source.slice(start,end+1);
}
let original;
export function snapshot(){
 return JSON.parse(sql(`select json_build_object('worker_status',(select status from workers where id='${info.worker}'),
 'worker_count',(select count(*) from workers),'qualification_count',(select count(*) from worker_qualifications),
 'qualification_hash',(select md5(jsonb_agg(to_jsonb(q) order by q.id)::text)from worker_qualifications q),
 'own_qualification',(select to_jsonb(q)from worker_qualifications q where id='${info.qualification}'))::text;`));
}
export function repair(sources){
 sql(`begin;update public.workers set status='inactive' where id='${info.worker}';
 ${sources['tool/review/employee_retirement_worker_binding_20261101/repair.sql.review-only']}commit;`);
 const value=snapshot();assert.equal(value.worker_status,'inactive');assert.equal(value.qualification_hash,original.qualification_hash);return value;
}
export function prepare(){
 validateEnvironment(process.env);
 const actual=JSON.parse(sql("select json_build_object('db',current_database(),'addr',host(inet_server_addr()),'role',current_user)::text"));
 assert.equal(actual.db,'retirement_fixture');assert.equal(actual.role,'postgres');assert.equal(actual.addr,process.env.SKO_QUALIFICATION_FIXTURE_SERVER_ADDR);
 const sources=sourceInputs();
 const feature=sources['supabase/migrations/20260920022000_harden_attendance_and_approval_privacy.sql'];
 const featureBody=feature.slice(0,feature.indexOf('$$;')+3);assert.ok(featureBody.includes('function private.has_company_feature('));
 const core=sources['supabase/migrations/20260922031000_cache_auth_uid_in_core_rls.sql'];
 const qualifications=sources['supabase/migrations/20260919024500_harden_qualification_rls.sql'];
 const privacy=sources['supabase/migrations/20260920205500_restrict_worker_private_documents.sql'];
 const flags=['can_approve_daily_report_edits','can_manage_attendance','can_manage_people','can_view_invoices','can_manage_invoices','can_view_admin_site_data','can_manage_admin_site_data','can_manage_payroll','can_manage_partner_chat','can_manage_vehicles','can_manage_routes'];
 sql(`begin;create schema auth;create schema private;create role authenticated;create role anon;create role service_role;
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 create function auth.jwt() returns jsonb language sql stable as $$select jsonb_build_object('sub',auth.uid(),'user_metadata','{}'::jsonb)$$;
 create table public.company_members(company_id uuid,user_id uuid,role text,primary key(company_id,user_id));
 create table public.user_profiles(user_id uuid,display_name text,phone text);
 create table public.company_approval_assignees(company_id uuid,user_id uuid);
 create table public.member_feature_permissions(company_id uuid,user_id uuid,${flags.map(k=>k+' boolean not null default false').join(',')});
 create table public.workers(id uuid primary key default gen_random_uuid(),company_id uuid,user_id uuid,affiliation text,name text,phone text,status text,unique(company_id,user_id));
 create table public.qualification_master(id uuid primary key,company_id uuid,name text,category text,issuer text,expiry_required boolean,notes text,is_active boolean,source_name text,source_reference text,source_updated_at date,external_source_id text,is_company_custom boolean);
 create table public.worker_qualifications(id uuid primary key,company_id uuid,worker_id uuid,qualification_master_id uuid,certificate_number text,issued_at date,expires_at date,issuer text,attachment_path text,attachment_back_path text,attachment_extra_paths text[],notes text,created_at timestamptz,updated_at timestamptz);
 ${sources['tool/review/employee_retirement_worker_binding_20261101/production-observed-baseline.sql']};
 revoke all on function public.ensure_current_user_worker() from public,anon;grant execute on function public.ensure_current_user_worker() to authenticated,service_role;
 ${featureBody}
 ${sources['supabase/migrations/20260930062500_fix_manager_vehicle_route_effective_permissions.sql']}
 revoke all on function public.current_feature_permissions() from public,anon;grant execute on function public.current_feature_permissions() to authenticated;
 revoke all on function private.has_company_feature(uuid,text) from public,anon;grant execute on function private.has_company_feature(uuid,text) to authenticated;
 insert into company_members values('${info.company}','${info.actor}','viewer');
 insert into user_profiles values('${info.actor}','Synthetic retired person','07000000000');
 insert into workers(id,company_id,user_id,affiliation,name,status)values
 ('${info.worker}','${info.company}','${info.actor}','employee','Existing retired person','inactive'),
 ('30000000-0000-0000-0000-000000000002','${info.company}','10000000-0000-0000-0000-000000000002','employee','Other person','active'),
 ('30000000-0000-0000-0000-000000000003','20000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000003','employee','Foreign company','active');
 insert into qualification_master(id,company_id,name,issuer,expiry_required,is_active,is_company_custom) values('${info.master}','${info.company}','Synthetic qualification','Synthetic issuer',true,true,false);
 insert into worker_qualifications values
 ('${info.qualification}','${info.company}','${info.worker}','${info.master}','KEPT-123','2025-01-01','2030-01-01','Synthetic issuer','${info.company}/${info.worker}/front.jpg','${info.company}/${info.worker}/back.jpg',array['${info.company}/${info.worker}/extra.jpg'],'preserved notes','2026-01-01T00:00:00Z','2026-01-02T00:00:00Z'),
 ('50000000-0000-0000-0000-000000000002','${info.company}','30000000-0000-0000-0000-000000000002','${info.master}','OTHER-PERSON',null,null,null,'other-person.jpg',null,array[]::text[],null,now(),now()),
 ('50000000-0000-0000-0000-000000000003','20000000-0000-0000-0000-000000000003','30000000-0000-0000-0000-000000000003','${info.master}','OTHER-COMPANY',null,null,null,'other-company.jpg',null,array[]::text[],null,now(),now());
 alter table company_members enable row level security;alter table workers enable row level security;alter table qualification_master enable row level security;alter table worker_qualifications enable row level security;
 ${selectedPolicy(core,'company_members_self_read')}
 ${selectedPolicy(core,'"company members can read workers"')}
 ${selectedPolicy(qualifications,'"company members can read qualification master"')}
 ${selectedPolicy(privacy,'"worker or people manager can read worker qualifications"')}
 grant usage on schema public,auth,private to authenticated;
 grant select on company_members,workers,qualification_master,worker_qualifications to authenticated;
 commit;`);
 assert.equal(sql("select md5(pg_get_functiondef('public.ensure_current_user_worker()'::regprocedure));"),'10565c7d5a53e45f37a4c6be0f58b538');
 original=snapshot();assert.equal(original.worker_status,'inactive');return {sources,original};
}
