import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {randomBytes,randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';
const here=path.dirname(fileURLToPath(import.meta.url));
const capture=JSON.parse(fs.readFileSync(path.join(here,'storage_session_catalog.json'),'utf8'));
const status=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
const origin=status.API_URL??status.api_url;const dbUrl=status.DB_URL??status.db_url;
for(const address of [origin,dbUrl]){const u=new URL(address);assert.equal(u.hostname,'127.0.0.1','Loopback fixture only');}
const anon=status.ANON_KEY??status.anon_key,service=status.SERVICE_ROLE_KEY??status.service_role_key;
assert.ok(typeof anon==='string'&&typeof service==='string');
const pg=await import(pathToFileURL(path.resolve(process.argv[3])).href);
const Client=pg.Client??pg.default?.Client;assert.equal(typeof Client,'function','Disposable PostgreSQL client available');
const db=new Client({connectionString:dbUrl});await db.connect();
const q=s=>"'"+s.replaceAll("'","''")+"'";
async function request(route,{token=anon,method='GET',json,body,headers={}}={}){
 const response=await fetch(origin+route,{method,headers:{apikey:anon,Authorization:`Bearer ${token}`,...(json?{'Content-Type':'application/json'}:{}),...headers},body:json?JSON.stringify(json):body,signal:AbortSignal.timeout(10000)});
 return response;
}
async function user(name){
 const password=randomBytes(24).toString('hex');const email=`${name}-${randomUUID()}@fixture.invalid`;
 let r=await request('/auth/v1/admin/users',{token:service,method:'POST',json:{email,password,email_confirm:true}});assert.equal(r.status,200,'Create fixture Auth user');
 const created=await r.json();r=await request('/auth/v1/token?grant_type=password',{method:'POST',json:{email,password}});assert.equal(r.status,200,'Real GoTrue password login');
 const session=await r.json();return {id:created.id,token:session.access_token,refresh:session.refresh_token};
}
const company=randomUUID(),worker=randomUUID(),requirement=randomUUID(),record=randomUUID();
let checks=0;
try{
 assert.equal((await db.query("select to_regclass('public.workers') is null and to_regclass('private.account_deletion_access_restrictions') is null as empty")).rows[0].empty,true,'Empty fixture application schema required');
 assert.equal((await db.query("select count(*)::int n from pg_policies where schemaname='storage' and tablename='objects'")).rows[0].n,0,'Fresh fixture Storage policies required');
 const users={own:await user('own'),manager:await user('manager'),owner:await user('owner'),other:await user('other')};
 await db.query(`create schema private;create type public.app_role as enum ('owner','admin','manager','worker','viewer');
 create table private.account_deletion_access_restrictions(user_id uuid);
 create table public.company_members(company_id uuid,user_id uuid,role public.app_role);
 create table public.member_feature_permissions(company_id uuid,user_id uuid,can_view_invoices boolean default false,can_manage_invoices boolean default false,can_manage_payroll boolean default false,can_manage_people boolean default false,can_manage_attendance boolean default false,can_approve_daily_report_edits boolean default false,can_manage_partner_chat boolean default false);
 create table public.workers(id uuid,company_id uuid,user_id uuid);
 create table public.document_requirements(id uuid,company_id uuid,is_active boolean,name text,scope text,sort_order integer);
 create table public.worker_document_statuses(id uuid,company_id uuid,worker_id uuid,requirement_id uuid,attachment_path text,attachment_paths text[],status text);
 create table private.document_submissions(company_id uuid,worker_id uuid,requested_by uuid,status text,upload_path text,attachment_path text,previous jsonb);
 create table public.company_approval_assignees(company_id uuid,user_id uuid);
 grant usage on schema private to authenticated;grant select on all tables in schema public to authenticated;`);
 for(const f of capture.functions)await db.query(f.definition);
 for(const table of ['workers','company_members','document_requirements','worker_document_statuses'])await db.query(`alter table public.${table} enable row level security`);
 for(const p of capture.business_read_policy_inventory){if(p.policyname==='company_members_owner_manage')continue;await db.query(`create policy ${JSON.stringify(p.policyname)} on public.${p.tablename} as ${p.permissive} for select to authenticated using (${p.qual})`);}
 for(const p of capture.storage_read_policy_inventory.filter(p=>p.policyname==='account_deletion_access_guard'||p.qual?.includes("bucket_id = 'worker-documents'")))await db.query(`create policy ${JSON.stringify(p.policyname)} on storage.objects as ${p.permissive} for select to authenticated using (${p.qual})`);
 const object=`${company}/${worker}/${requirement}/${record}/fixture.png`;
 await db.query(`insert into public.company_members values(${q(company)},${q(users.own.id)},'worker'),(${q(company)},${q(users.manager.id)},'manager'),(${q(company)},${q(users.owner.id)},'owner'),(${q(randomUUID())},${q(users.other.id)},'admin');
 insert into public.member_feature_permissions(company_id,user_id,can_manage_people) values(${q(company)},${q(users.manager.id)},true);
 insert into public.workers values(${q(worker)},${q(company)},${q(users.own.id)});
 insert into public.document_requirements values(${q(requirement)},${q(company)},true,'fixture','internal',1);
 insert into public.worker_document_statuses values(${q(record)},${q(company)},${q(worker)},${q(requirement)},${q(object)},array[${q(object)}],'submitted');`);
 let r=await request('/storage/v1/bucket',{token:service,method:'POST',json:{id:'worker-documents',name:'worker-documents',public:false}});assert.equal(r.status,200,'Create private fixture bucket');
 const bytes=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6oAAAAABJRU5ErkJggg==','base64');
 r=await request('/storage/v1/object/worker-documents/'+object,{token:service,method:'POST',body:bytes,headers:{'Content-Type':'image/png','Cache-Control':'max-age=0'}});assert.equal(r.status,200,'Upload generated fixture bytes');
 const download=token=>request('/storage/v1/object/authenticated/worker-documents/'+object,{token});
 async function allowed(token){const response=await download(token);assert.equal(response.status,200,'Authorized actual Storage download');assert.deepEqual(Buffer.from(await response.arrayBuffer()),bytes);checks++;}
 async function denied(token){const response=await download(token);assert.ok([400,401,403,404].includes(response.status),'Denied actual Storage download');checks++;}
 await db.query(`update public.member_feature_permissions set can_manage_people=false where user_id=${q(users.manager.id)}`);
 await allowed(users.manager.token);console.log('REPRODUCED actual Storage HTTP: baseline role-only manager reads despite feature OFF');
 await db.query(fs.readFileSync(path.join(here,'storage_session_feature_boundary.sql.review-only'),'utf8'));
 await denied(users.manager.token);
 await db.query(`update public.member_feature_permissions set can_manage_people=true where user_id=${q(users.manager.id)}`);
 await denied(anon);await denied(users.other.token);await allowed(users.own.token);await allowed(users.owner.token);await allowed(users.manager.token);
 await db.query('insert into private.account_deletion_access_restrictions values($1)',[users.own.id]);await denied(users.own.token);
 await db.query('delete from private.account_deletion_access_restrictions where user_id=$1',[users.own.id]);await allowed(users.own.token);
 r=await request('/storage/v1/object/sign/worker-documents/'+object,{token:users.manager.token,method:'POST',json:{expiresIn:2}});assert.equal(r.status,200,'Actual Storage signed URL issuance');
 const signed=await r.json();const relative=signed.signedURL??signed.signedUrl;assert.ok(typeof relative==='string');
 assert.ok(relative.startsWith('/object/sign/')||relative.startsWith('/storage/v1/object/sign/'),'Only local signed Storage path');
 const signedUrl=new URL(origin+(relative.startsWith('/storage/v1/')?'':'/storage/v1')+relative);assert.equal(signedUrl.origin,new URL(origin).origin);
 const signedDownload=()=>fetch(signedUrl,{cache:'no-store',signal:AbortSignal.timeout(10000)});
 await db.query(`update public.member_feature_permissions set can_manage_people=false where user_id=${q(users.manager.id)}`);
 await denied(users.manager.token);
 const beforeExpiry=await signedDownload();assert.ok([200,400,401,403,404].includes(beforeExpiry.status));await beforeExpiry.arrayBuffer();
 console.log(`OBSERVED prior signed URL after feature revocation: ${beforeExpiry.status===200?'still usable before expiry (remaining bearer-URL exposure)':'origin refused'}`);
 await new Promise(resolve=>setTimeout(resolve,5000));
 const expired=await signedDownload();assert.ok([400,401,403,404].includes(expired.status),'Actual origin rejects expired signed URL');checks++;
 const claims=JSON.parse(Buffer.from(users.own.token.split('.')[1],'base64url').toString());assert.ok(typeof claims.session_id==='string');
 r=await request('/auth/v1/logout?scope=local',{token:users.own.token,method:'POST'});assert.ok([200,204].includes(r.status),'Real GoTrue logout');
 assert.equal((await db.query('select count(*)::int n from auth.sessions where id=$1',[claims.session_id])).rows[0].n,0,'Session actually removed');
 const oldJwtResponse=await download(users.own.token);assert.ok([200,400,401,403,404].includes(oldJwtResponse.status));await oldJwtResponse.arrayBuffer();
 console.log(`OBSERVED old access JWT after actual logout/session removal: ${oldJwtResponse.status===200?'still permits Storage until JWT expiry/current guard allows (remaining gap)':'Storage refused'}`);
 r=await request('/auth/v1/token?grant_type=refresh_token',{method:'POST',json:{refresh_token:users.own.refresh}});assert.ok([400,401,403].includes(r.status),'Logged-out refresh token denied');checks++;
 console.log(`PASS ${checks} actual local GoTrue/Storage HTTP checks. No production/CDN/cache-distribution equivalence or immediate old-JWT/issued-URL revocation claim.`);
}catch(e){console.error('Fixture verification failed:',e.code??'',e.message);process.exitCode=1;}finally{await db.end();}
