// Isolated SQL object-row DELETE proof, never a Storage bytes/lifecycle proof.
import fs from 'node:fs';
import assert from 'node:assert/strict';
const {PGlite}=await import(process.argv[2]);
const db=new PGlite();
const company='10000000-0000-0000-0000-000000000001';
const worker='10000000-0000-0000-0000-000000000003';
const owner='10000000-0000-0000-0000-000000000099';
const admin='10000000-0000-0000-0000-000000000002';
const path=`${company}/2030/04/${worker}/capture.jpg`;
try {
 await db.exec(fs.readFileSync('supabase/tests/capture_storage_retention_bootstrap.sql','utf8'));
 const original=fs.readFileSync('supabase/migrations/20260920211200_allow_orphan_attendance_evidence_cleanup.sql','utf8');
 assert.equal((original.match(/create policy/g)||[]).length,1);
 assert.ok(original.trim().endsWith(');'));
 const candidate=original.trim().slice(0,-2)+`\n and not exists(select 1 from public.attendance_verifications av where av.photo_storage_path=storage.objects.name)\n and not private.fixture_archive_referenced(storage.objects.name)\n);`;
 const read=fs.readFileSync('supabase/migrations/20260920210500_restrict_attendance_evidence_privacy.sql','utf8');
 const selectPolicy=read.slice(read.indexOf('create policy "attendance_evidence_read"'),read.indexOf('create policy "attendance_evidence_insert"'));
 await db.exec(selectPolicy);
 await db.exec('set role authenticated');
 await assert.rejects(db.query('select * from private.fixture_archive'),/permission denied/);
 await db.exec('reset role');
 for(const mode of ['baseline','candidate']) {
  await db.exec(mode==='baseline'?original:candidate);
  for(const actor of [owner,admin]) for(const scenario of ['orphan','live','archive','other_bucket','other_company','malformed','archive_read_failure']) {
   await db.exec('reset role; truncate storage.objects,public.attendance_verifications,private.fixture_archive');
   let name=scenario==='other_company'?path.replace(company,'20000000-0000-0000-0000-000000000001'):scenario==='malformed'?'invalid/path':path;
   await db.query('insert into storage.objects(bucket_id,name) values($1,$2)',[scenario==='other_bucket'?'other-bucket':'attendance-evidence',name]);
   if(scenario==='live') await db.query('insert into public.attendance_verifications values($1)',[name]);
   if(scenario==='archive') await db.query('insert into private.fixture_archive values($1)',[name]);
   await db.query("select set_config('test.actor',$1,false),set_config('test.archive_read_failure',$2,false)",[actor,String(scenario==='archive_read_failure')]);
   await db.exec('set role authenticated');
   let failure=false;
   try {await db.query('delete from storage.objects where name=$1',[name]);} catch(error) {
    if(error.message!=='synthetic archive lookup unavailable') throw error;
    failure=true;
   }
   await db.exec('reset role');
   const rows=await db.query('select count(*)::int as n from storage.objects');
   const eligible=['orphan','live','archive','archive_read_failure'].includes(scenario);
   const oldDeletes=eligible&&(actor===admin||scenario!=='live');
   const expectedDelete=mode==='baseline'?oldDeletes:scenario==='orphan';
   assert.equal(rows.rows[0].n,expectedDelete?0:1,`${mode}/${actor}/${scenario}`);
   if(mode==='candidate'&&scenario==='archive_read_failure') assert.equal(failure,true,'archive lookup errors must abort DELETE');
  }
 }
 console.log('PASS actual isolated RLS DELETE baseline/candidate: owner/admin, orphan/live/archive, bucket/company/path, lookup error; object rows only');
} finally {await db.close();}
