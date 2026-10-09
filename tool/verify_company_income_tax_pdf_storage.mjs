// Isolated Storage policy/object-row proof; not upload/download bytes or JWT proof.
import fs from 'node:fs';
import assert from 'node:assert/strict';
const {PGlite}=await import(process.argv[2]);
const db=new PGlite();
const company='10000000-0000-0000-0000-000000000001';
const other='20000000-0000-0000-0000-000000000001';
const owner='10000000-0000-0000-0000-000000000011';
const admin='10000000-0000-0000-0000-000000000012';
const worker='10000000-0000-0000-0000-000000000013';
const otherAdmin='20000000-0000-0000-0000-000000000012';
const id='30000000-0000-0000-0000-000000000001';
const hash='a'.repeat(64);
const bucket='company-income-tax-tables';
const path=`${company}/${id}/1/${hash}.pdf`;
async function actor(actorId,operation,role='authenticated',allowed=true) {
 await db.exec('reset role');
 await db.query("select set_config('test.actor',$1,false),set_config('test.account_allowed',$2,false),set_config('storage.operation',$3,false)",[actorId,String(allowed),operation]);
 await db.exec(`set role ${role}`);
}
async function select(name=path,targetBucket=bucket) {
 return (await db.query('select * from storage.objects where bucket_id=$1 and name=$2',[targetBucket,name])).rows;
}
async function insert(name=path,targetBucket=bucket) {
 await db.query('insert into storage.objects(bucket_id,name) values($1,$2)',[targetBucket,name]);
}
const value={calendar_year:2030,kind:'monthly',starts_on:'2030-01-01',ends_before:'2031-01-01',document_hash:hash,storage_path:path,source_url:'https://example.test/fixture.pdf',publisher:'Fixture only',file_name:'fixture.pdf'};
async function register(version=0,payload=value) {
 return (await db.query('select public.register_company_income_tax_table($1,$2,$3,$4::jsonb,true) as result',[company,id,version,JSON.stringify(payload)])).rows[0].result;
}
try {
 await db.exec(fs.readFileSync('supabase/tests/company_income_tax_table_registry_bootstrap.sql','utf8'));
 await db.exec(fs.readFileSync('supabase/tests/company_income_tax_pdf_storage_bootstrap.sql','utf8'));
 await db.exec(fs.readFileSync('supabase/migrations/20261009155006_company_income_tax_table_registry.sql','utf8'));
 await db.exec(fs.readFileSync('supabase/migrations/20261009155952_company_income_tax_private_pdf_storage.sql','utf8'));
 const config=(await db.query('select * from storage.buckets where id=$1',[bucket])).rows[0];
 assert.equal(config.public,false);assert.equal(config.file_size_limit,10485760);assert.deepEqual(config.allowed_mime_types,['application/pdf']);
 await actor(admin,'object.upload');
 await assert.rejects(register(),/not uploaded/);
 const registry=(await db.query('select public.read_company_income_tax_tables($1,$2,$3) as result',[company,'2030-01-01','monthly'])).rows[0].result;
 assert.deepEqual(registry.tables,[]);assert.deepEqual(registry.history,[]);
 for(const actorId of [worker,otherAdmin,'']) {
  await actor(actorId,'object.upload');await assert.rejects(insert(),/row-level security/);
 }
 await actor(admin,'object.upload','authenticated',false);await assert.rejects(insert(),/row-level security/);
 await actor(owner,'object.upload','anon');await assert.rejects(insert(),/row-level security/);
 await actor(owner,'object.upload');
 for(const malformed of [
  path.replace(company,other),path.replace('/1/','/0/'),path.replace('/1/','/9999999999999999999/'),
  path.replace(id,'not-uuid'),path.replace(hash,'fake'),path+'/extra',path.replace('.pdf','.txt'),
 ]) await assert.rejects(insert(malformed),/row-level security/);
 for(const operation of ['', 'object.upload_update','object.upload_signed','object.sign_upload_url']) {
  await actor(owner,operation);await assert.rejects(insert(),/row-level security/);
 }
 await actor(owner,'storage.object.upload');await insert();
 await assert.rejects(insert(),/duplicate key/);
 await actor(admin,'object.upload');const saved=await register();
 assert.equal(saved.official_document_verified,false);assert.equal(saved.calculation_rules_verified,false);assert.equal(saved.common_data_approved,false);
 const revisedPath=`${company}/${id}/2/${hash}.pdf`;
 const revised={...value,storage_path:revisedPath};
 await assert.rejects(register(1,revised),/not uploaded/);
 await insert(revisedPath);await register(1,revised);
 for(const operation of ['object.get_authenticated','storage.object.get_authenticated','object.get_authenticated_info','object.head_authenticated_info','object.sign','storage.object.sign']) {
  await actor(admin,operation);assert.equal((await select()).length,1);assert.equal((await select(revisedPath)).length,1);
 }
 for(const operation of ['', 'object.list','object.list_v2','object.sign_many','object.get_signed','object.upload_update']) {
  await actor(admin,operation);assert.equal((await select()).length,0,operation);
 }
 for(const actorId of [worker,otherAdmin,'']) {
  await actor(actorId,'object.get_authenticated');assert.equal((await select()).length,0);
 }
 await actor(admin,'object.get_authenticated','authenticated',false);assert.equal((await select()).length,0);
 await actor(owner,'object.get_authenticated','anon');assert.equal((await select()).length,0);
 await actor(owner,'object.get_authenticated');
 assert.equal((await db.query('update storage.objects set name=$1 where bucket_id=$2 and name=$3 returning *',[path+'.replaced',bucket,path])).rows.length,0);
 assert.equal((await db.query('delete from storage.objects where bucket_id=$1 and name=$2 returning *',[bucket,path])).rows.length,0);
 assert.equal((await select()).length,1,'old PDF row must remain after no-op overwrite/delete');
 await actor(owner,'object.upload');await insert('other.pdf','other-bucket');
 await actor(owner,'object.list');assert.equal((await select('other.pdf','other-bucket')).length,1,'other bucket access must retain existing policy');
 await db.exec('reset role');await db.query('delete from public.companies where id=$1',[company]);
 await actor(owner,'object.get_authenticated');assert.equal((await select()).length,0,'deleted company stale membership cannot read retained bytes row');
 await actor(owner,'object.upload');await assert.rejects(insert(`${company}/${id}/3/${hash}.pdf`),/row-level security/);
 console.log('PASS staged private PDF Storage policies: dedicated private config, admin/company/account/path upload, operation-specific read/no listing, no overwrite/delete/anon, object-required unverified metadata, retained old paths, other bucket unchanged');
} finally {await db.close();}
