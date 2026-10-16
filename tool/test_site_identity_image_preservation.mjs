import { PGlite } from '@electric-sql/pglite';
import fs from 'node:fs';
import assert from 'node:assert/strict';
const db=new PGlite();
const sourceRoot=process.argv[2]??'.';
const appRoot=process.argv[3]??'.';
const repository=fs.readFileSync(appRoot+'/lib/features/sites/site_cloud_repository.dart','utf8');
const loadPhotos=repository.split('Future<List<SitePhotoRecord>> loadPhotos(String siteId) async {')[1]?.split('Future<bool> uploadPhoto')[0];
assert.ok(loadPhotos);assert.ok(loadPhotos.includes(".eq('site_id', siteId)"));assert.ok(loadPhotos.includes("createSignedUrl(path, 3600)"));assert.ok(!loadPhotos.includes('display_group'));
const id=n=>'00000000-0000-0000-0000-'+String(n).padStart(12,'0');
const source=JSON.parse(fs.readFileSync('tool/fixtures/site_image_safety/catalog.json','utf8')).records;
// Minimal disposable dependencies, not a substitute for a complete Supabase instance.
await db.exec(`create role anon;create role authenticated;create schema auth;create schema private;create schema storage;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
create table public.companies(id uuid primary key);
create table public.company_members(company_id uuid,user_id uuid,role text);
create table public.company_approval_assignees(company_id uuid,user_id uuid);
create table public.sites(id uuid primary key,company_id uuid,name text,formal_name text);
create table public.attendance_entries(id uuid primary key,site_id uuid references public.sites(id),amount integer);
create table private.document_deliveries(id uuid primary key,sender_company_id uuid,recipient_company_id uuid);
create table private.company_data_delivery_items(id uuid primary key,delivery_id uuid,payload_kind text,payload jsonb);
create table private.site_share_inbox(data_item_id uuid primary key,recipient_company_id uuid,status text);
create table private.site_photo_requests(storage_path text,company_id uuid,requested_by uuid,status text);
create table private.account_deletion_access_restrictions(user_id uuid);
create table storage.objects(name text primary key,bucket_id text);
grant usage on schema public,private,storage,auth to authenticated;
grant select on public.company_members to authenticated;
`);
const cols=source.filter(x=>x.kind==='column').map(x=>`"${x.definition.name}" ${x.definition.type}${x.definition.notnull?' not null':''}`).join(',');
await db.exec('create table public.site_entrance_photos('+cols+')');
for(const x of source.filter(x=>x.kind==='constraint'))await db.exec(`alter table public.site_entrance_photos add constraint "${x.definition.name}" ${x.definition.definition}`);
for(const x of source.filter(x=>x.kind==='function'))await db.exec(x.definition.definition);
for(const table of ['public.site_entrance_photos','storage.objects'])await db.exec(`alter table ${table} enable row level security;grant select on ${table} to authenticated`);
for(const {definition:p} of source.filter(x=>x.kind==='policy'&&['SELECT','ALL'].includes(x.definition.cmd))){
 await db.exec(`create policy "${p.policyname}" on ${p.schemaname}.${p.tablename} as ${p.permissive} for ${p.cmd} to ${p.roles.join(',')} using (${p.qual})${p.with_check?' with check ('+p.with_check+')':''}`);
}
for(let n=1;n<=3;n++){
 await db.query('insert into companies values($1)',[id(n)]);
 await db.query("insert into company_members values($1,$2,'admin')",[id(n),id(100+n)]);
 await db.query("insert into sites values($1,$2,'same','正式名')",[id(10+n),id(n)]);
 const path=id(n)+'/'+id(10+n)+'/original.jpg';
 await db.query('insert into site_entrance_photos values($1,$2,1,$3,now())',[id(10+n),id(n),path]);
 await db.query("insert into storage.objects values($1,'site-entrance-photos')",[path]);
 await db.query('insert into attendance_entries values($1,$2,123)',[id(500+n),id(10+n)]);
}
await db.query('insert into private.document_deliveries values($1,$2,$3)',[id(201),id(1),id(2)]);
await db.query("insert into private.company_data_delivery_items values($1,$2,'site_share',$3)",[id(301),id(201),JSON.stringify({source_site_id:id(11)})]);
await db.query("insert into private.site_share_inbox values($1,$2,'accepted')",[id(301),id(2)]);
const snapshot=async()=>JSON.stringify((await db.query(`select jsonb_build_object('photos',(select jsonb_agg(to_jsonb(p) order by site_id) from site_entrance_photos p),'objects',(select jsonb_agg(to_jsonb(o) order by name) from storage.objects o),'attendance',(select jsonb_agg(to_jsonb(a) order by id) from attendance_entries a)) v`)).rows[0].v);
const original=await snapshot();
await db.exec(fs.readFileSync(sourceRoot+'/tool/staged/site_identity_links.sql','utf8'));
await db.exec(fs.readFileSync(sourceRoot+'/tool/staged/site_identity_company_rollout.sql','utf8'));
const actor=async n=>{await db.exec('reset role');await db.query("select set_config('test.uid',$1,false)",[id(100+n)]);await db.exec('set role authenticated');};
for(let n=1;n<=3;n++){await actor(n);await db.query('select site_identity_private.set_rollout($1,true)',[id(n)]);}
async function check(){
 for(let n=1;n<=3;n++){
  await actor(n);
  const photos=(await db.query('select site_id,storage_path from site_entrance_photos')).rows;
  assert.equal(photos.length,1);assert.equal(photos[0].site_id,id(10+n));
  const objects=(await db.query('select name from storage.objects')).rows;
  assert.deepEqual(objects.map(x=>x.name),[id(n)+'/'+id(10+n)+'/original.jpg']);
  for(let other=1;other<=3;other++)if(other!==n)assert.equal((await db.query('select * from site_entrance_photos where site_id=$1',[id(10+other)])).rows.length,0);
 }
 await db.exec('reset role');assert.equal(await snapshot(),original);
}
await check();await actor(2);
const linked=(await db.query('select site_identity_change_link($1,$2,$3,0,false) v',[id(2),id(12),id(301)])).rows[0].v;
assert.equal(linked.revision,1);await check();
await actor(2);const detached=(await db.query('select site_identity_change_link($1,$2,null,1,true) v',[id(2),id(12)])).rows[0].v;
assert.notEqual(detached.display_group,linked.display_group);await check();
// Exercise the second actual Storage policy with a synthetic pending request.
await db.query("insert into private.site_photo_requests values('pending-only.jpg',$1,$2,'pending')",[id(2),id(102)]);
await db.exec("insert into storage.objects values('pending-only.jpg','site-entrance-photos')");
await actor(2);assert.equal((await db.query("select name from storage.objects where name='pending-only.jpg'")).rows.length,1);
await actor(1);assert.equal((await db.query("select name from storage.objects where name='pending-only.jpg'")).rows.length,0);
await db.exec('reset role');await db.query('insert into private.account_deletion_access_restrictions values($1)',[id(102)]);
await actor(2);assert.equal((await db.query('select * from site_entrance_photos')).rows.length,0);assert.equal((await db.query('select * from storage.objects')).rows.length,0);
await db.exec('reset role;set role anon');await assert.rejects(()=>db.query('select * from site_entrance_photos'),/permission denied/);
console.log('PASS actual photo columns/constraints and catalog-derived read policies: own access, cross-company refusal, link/unlink old IDs/paths/attendance unchanged, request-path boundary, account guard, anon denied');
console.log('LIMIT: isolated PostgreSQL-WASM, minimal dependencies, Storage SELECT subset only; no HTTP signed URL, real bytes, live RLS execution, image-display integration or complete unrelated-policy proof');
await db.close();
