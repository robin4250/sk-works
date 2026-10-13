import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { pathToFileURL } from 'node:url';
const { PGlite } = await import(pathToFileURL(process.argv[2]).href);
const db = new PGlite();
const company='10000000-0000-0000-0000-000000000001';
const worker='10000000-0000-0000-0000-000000000002';
const qualification='10000000-0000-0000-0000-000000000003';
const prefix=`${company}/${worker}/${qualification}/`;
await db.exec(`create role anon;create role authenticated;create schema private;create schema storage;
create table storage.objects(id int generated always as identity primary key,bucket_id text,name text);
alter table storage.objects enable row level security;
grant usage on schema storage,private to authenticated;
grant select,update,delete on storage.objects to authenticated;
create policy fixture_read on storage.objects for select to authenticated using(true);
create policy fixture_update on storage.objects for update to authenticated using(true) with check(true);
create policy fixture_delete on storage.objects for delete to authenticated using(true);
create table public.worker_qualifications(id uuid primary key,company_id uuid,worker_id uuid,attachment_path text,attachment_back_path text);
create table private.document_delivery_items(bucket text,path text);
create table private.worker_qualification_history(snapshot jsonb);
create table private.qualification_submissions(attachment_path text,previous jsonb);
insert into worker_qualifications values('${qualification}','${company}','${worker}','legacy-front.jpg','legacy-back.jpg');
insert into storage.objects(bucket_id,name) values('qualification-certificates','legacy-front.jpg'),('qualification-certificates','legacy-back.jpg'),('qualification-certificates','${prefix}extra.jpg'),('qualification-certificates','${prefix}replacement.jpg'),('qualification-certificates','${prefix}orphan.jpg');`);
await db.exec(readFileSync('supabase/migrations/20261010222157_add_qualification_certificate_extra_photos.sql','utf8'));
await db.exec(readFileSync('supabase/migrations/20261010222753_protect_qualification_photo_snapshots.sql','utf8'));
await db.query('update worker_qualifications set attachment_extra_paths=$1 where id=$2',[[`${prefix}extra.jpg`],qualification]);
await assert.rejects(db.query('update worker_qualifications set attachment_extra_paths=$1 where id=$2',[['other-company/extra.jpg'],qualification]),e=>e.code==='22023');
await assert.rejects(db.query('update worker_qualifications set attachment_extra_paths=$1 where id=$2',[[`${prefix}missing.jpg`],qualification]),e=>e.code==='22023');
await assert.rejects(db.query('update worker_qualifications set attachment_extra_paths=$1 where id=$2',[[`${prefix}extra.jpg`,`${prefix}extra.jpg`],qualification]),e=>e.code==='22023');
await db.query('update worker_qualifications set attachment_extra_paths=$1 where id=$2',[[`${prefix}replacement.jpg`],qualification]);
await db.exec('set role authenticated');
for(const name of ['legacy-front.jpg','legacy-back.jpg',`${prefix}extra.jpg`,`${prefix}replacement.jpg`]) {
 assert.equal((await db.query('delete from storage.objects where name=$1 returning id',[name])).rows.length,0);
 assert.equal((await db.query('update storage.objects set name=$1 where name=$1 returning id',[name])).rows.length,0);
}
assert.equal((await db.query('delete from storage.objects where name=$1 returning id',[`${prefix}orphan.jpg`])).rows.length,1);
await assert.rejects(db.query('select * from private.qualification_photo_history'),e=>e.code==='42501');
await db.exec('reset role');
await db.query('delete from worker_qualifications where id=$1',[qualification]);
await db.exec('set role authenticated');
assert.equal((await db.query('delete from storage.objects where name=$1 returning id',[`${prefix}replacement.jpg`])).rows.length,0);
await db.exec('reset role');
await db.query("insert into private.document_delivery_items values('qualification-certificates',$1)",['delivery-only.jpg']);
await db.query("insert into storage.objects(bucket_id,name) values('qualification-certificates',$1)",['delivery-only.jpg']);
await db.exec('set role authenticated');
assert.equal((await db.query('delete from storage.objects where name=$1 returning id',['delivery-only.jpg'])).rows.length,0);
await db.exec('reset role');
await db.query("insert into private.worker_qualification_history values($1)",[JSON.stringify({attachment_back_path:'approval-back.jpg',attachment_extra_paths:['approval-extra.jpg']})]);
await db.query("insert into private.qualification_submissions values($1,$2)",['submission.jpg',JSON.stringify({attachment_back_path:'previous-back.jpg',attachment_extra_paths:['previous-extra.jpg']})]);
for(const name of ['approval-back.jpg','approval-extra.jpg','submission.jpg','previous-back.jpg','previous-extra.jpg']) {
 await db.query("insert into storage.objects(bucket_id,name) values('qualification-certificates',$1)",[name]);
}
await db.exec('set role authenticated');
for(const name of ['approval-back.jpg','approval-extra.jpg','submission.jpg','previous-back.jpg','previous-extra.jpg']) {
 assert.equal((await db.query('delete from storage.objects where name=$1 returning id',[name])).rows.length,0);
}
console.log('PASS qualification extra paths: cross-company/missing/duplicate denial; front/back/extra live + history + delivery retained; orphan cleanup allowed; private archive inaccessible');
await db.close();
