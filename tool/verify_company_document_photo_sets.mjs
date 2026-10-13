import fs from 'node:fs';
import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
const {PGlite} = await import(pathToFileURL(process.argv[2]).href);
const db = new PGlite();
try {
await db.exec(`create role authenticated; create schema auth; create schema storage;
create function auth.uid() returns uuid language sql as $$ select nullif(current_setting('fixture.uid',true),'')::uuid $$;
create table public.company_members(company_id uuid, user_id uuid, role text);
create table public.company_required_documents(id uuid primary key, company_id uuid, attachment_path text);
create table storage.objects(name text, bucket_id text); alter table storage.objects enable row level security;
insert into company_required_documents values('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000001','old-legacy.jpg');`);
await db.exec(fs.readFileSync('supabase/migrations/20261010222245_company_document_photo_sets.sql','utf8'));
const old=(await db.query('select attachment_path, attachment_paths from company_required_documents')).rows[0];
assert.equal(old.attachment_path,'old-legacy.jpg'); assert.deepEqual(old.attachment_paths,[]);
const front='00000000-0000-0000-0000-000000000001/00000000-0000-0000-0000-000000000002/front.jpg';
const back=front.replace('front','back');
await db.query('update company_required_documents set attachment_path=$1,attachment_paths=$2',[front,[front,back]]);
assert.deepEqual((await db.query('select attachment_paths from company_required_documents')).rows[0].attachment_paths,[front,back]);
await assert.rejects(db.query('update company_required_documents set attachment_paths=$1',[[front,front]]));
await assert.rejects(db.query('update company_required_documents set attachment_path=$1,attachment_paths=$2',['other/evil.jpg',['other/evil.jpg']]));
await assert.rejects(db.query('update company_required_documents set attachment_paths=$1',[[back,front]]));
await db.query('update company_required_documents set attachment_path=$1',[back]);
assert.deepEqual((await db.query('select attachment_paths from company_required_documents')).rows[0].attachment_paths,[back]);
await db.exec('update company_required_documents set attachment_path=null');
assert.deepEqual((await db.query('select attachment_paths from company_required_documents')).rows[0].attachment_paths,[]);
await db.exec(`grant usage on schema auth,storage to authenticated;
grant select on company_required_documents,company_members,storage.objects to authenticated;
insert into company_members values
('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000010','admin'),
('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000011','viewer'),
('00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000012','admin');`);
await db.query('update company_required_documents set attachment_path=$1,attachment_paths=$2',[front,[front,back]]);
await db.query('insert into storage.objects values ($1,$2),($3,$2)',['company-required-documents-placeholder','company-required-documents',back]);
for(const [actor,count] of [['10',1],['11',0],['12',0]]) {
 await db.exec('begin');
 try {
  await db.exec('set local role authenticated');
  await db.query("select set_config('fixture.uid',$1,true)",['00000000-0000-0000-0000-0000000000'+actor]);
  assert.equal((await db.query('select count(*)::int n from storage.objects')).rows[0].n,count);
 } finally {await db.exec('rollback');}
}
console.log('PASS: additive preservation, ordered set, duplicate/path/primary rejection, legacy replace/delete compatibility; admin/viewer/cross-company Storage read matrix');
} finally {await db.close();}
