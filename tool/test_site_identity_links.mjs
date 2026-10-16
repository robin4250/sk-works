import { PGlite } from '@electric-sql/pglite';
import fs from 'node:fs';
import assert from 'node:assert/strict';
const db=new PGlite();
const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
await db.exec(`create role anon;create role authenticated;create schema auth;create schema private;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
create table public.company_members(company_id uuid,user_id uuid,role text);
create table public.sites(id uuid primary key,company_id uuid,name text,formal_name text);
create table private.document_deliveries(id uuid primary key,sender_company_id uuid,recipient_company_id uuid);
create table private.company_data_delivery_items(id uuid primary key,delivery_id uuid,payload_kind text,payload jsonb);
create table private.site_share_inbox(data_item_id uuid primary key,recipient_company_id uuid,status text);
create table public.attendance_entries(id uuid primary key,site_id uuid,amount integer);
`);
for(let n=1;n<=4;n++)await db.query('insert into public.company_members values($1,$2,$3);',[id(n),id(100+n),'admin']);
for(let n=1;n<=4;n++)await db.query('insert into public.sites values($1,$2,$3,$4);',[id(10+n),id(n),'same','正式名']);
await db.exec(fs.readFileSync('tool/staged/site_identity_links.sql','utf8'));
async function actor(n){await db.query("select set_config('test.uid',$1,false)",[id(100+n)]);}
async function proof(n,from,to){await db.query('insert into private.document_deliveries values($1,$2,$3)',[id(200+n),id(from),id(to)]);await db.query("insert into private.company_data_delivery_items values($1,$2,'site_share',$3::jsonb)",[id(300+n),id(200+n),JSON.stringify({source_site_id:id(10+from)})]);await db.query("insert into private.site_share_inbox values($1,$2,'pending')",[id(300+n),id(to)]);}
async function link(company,n,rev=0,unlink=false){return (await db.query('select public.site_identity_change_link($1,$2,$3,$4,$5) v',[id(company),id(10+company),n===null?null:id(300+n),rev,unlink])).rows[0].v;}
await proof(1,1,2);await actor(2);const b=await link(2,1);assert.equal(b.revision,1);
assert.deepEqual(await link(2,1,1),b,'same current choice is idempotent');
await assert.rejects(()=>link(2,1,0),/stale/);
await actor(3);await assert.rejects(()=>link(3,1),/received site share/);
await proof(2,2,3);await actor(3);const c=await link(3,2);assert.equal(c.display_group,b.display_group);
await db.query('insert into public.attendance_entries values($1,$2,123)',[id(501),id(13)]);
await actor(2);const detached=await link(2,null,1,true);assert.notEqual(detached.display_group,b.display_group);
assert.equal((await db.query('select display_group from site_identity_private.selections where site_id=$1',[id(13)])).rows[0].display_group,c.display_group,'other company selection unchanged');
assert.equal((await db.query('select amount from public.attendance_entries')).rows[0].amount,123);
await actor(1);assert.equal((await db.query("select public.site_identity_lookup($1,'正式名') v",[id(1)])).rows[0].v.length,1,'same formal name never automatically merges');
await db.exec('set role authenticated');await assert.rejects(()=>db.query('select * from site_identity_private.selections'),/permission denied/);await db.exec('reset role');
await db.exec('set role anon');await assert.rejects(()=>db.query('select public.site_identity_lookup($1,$2)',[id(1),'正式名']),/permission denied/);await db.exec('reset role');
await db.query("update public.company_members set role='member' where company_id=$1",[id(4)]);await actor(4);await assert.rejects(()=>link(4,null,0,true),/administrator/);
assert.equal((await db.query('select count(*)::int n from public.sites')).rows[0].n,4);
console.log('PASS: received-proof scope, stable IDs, idempotent current choice, revision CAS, directional detach, legacy attendance retained, exact own search, table ACL and role denial');

// Reverse sharing changes the receiver only, preserving the already linked third party.
await proof(3,3,1);await actor(1);const a=await link(1,3);assert.equal(a.display_group,c.display_group);
const roots=(await db.query('select site_id,id from site_identity_private.roots')).rows;
const ar=roots.find(x=>x.site_id===id(11)).id;
const br=roots.find(x=>x.site_id===id(12)).id;
await db.query('update site_identity_private.selections set vote_root=$1 where site_id=$2',[ar,id(11)]);
await db.query('update site_identity_private.selections set vote_root=$1 where site_id=$2',[br,id(13)]);
// Repeated sites from company 3 must not create extra votes.
for(let k=61;k<=63;k++){
 await db.query("insert into public.sites values($1,$2,'extra','extra')",[id(k),id(3)]);
 const r=(await db.query('select site_identity_private.ensure_root($1,$2) r',[id(3),id(k)])).rows[0].r;
 await db.query('update site_identity_private.selections set display_group=$1,vote_root=$2 where home_root=$3',[a.display_group,br,r]);
}
const lookup=async()=> (await db.query('select public.site_identity_lookup($1,$2) v',[id(1),'正式名'])).rows[0].v[0];
const rep=(await lookup()).representative_id;
assert.equal((await lookup()).representative_id,rep,'tie result is stable');
const candidates=(await db.query('select r.id from site_identity_private.roots r join site_identity_private.selections v on v.vote_root=r.id where v.display_group=$1 group by r.id,r.created_at order by count(distinct v.company_id) desc,r.created_at,r.id',[a.display_group])).rows;
assert.equal(rep,candidates[0].id);
assert.equal((await db.query('select count(distinct company_id)::int n from site_identity_private.selections where display_group=$1 and vote_root=$2',[a.display_group,br])).rows[0].n,1);
console.log('PASS: reverse direction preserves third party; repeated local records count one company; representative tie is stable');
await db.close();
