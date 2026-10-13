// Metadata/SQL verification only: no real Storage bytes, PDF parsing or tax calculation.
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
const nextId='30000000-0000-0000-0000-000000000002';
const distinct='30000000-0000-0000-0000-000000000003';
function metadata(tableId,year,version=1,targetCompany=company,overrides={}) {
 const document_hash='a'.repeat(64);
 return {calendar_year:year,kind:'monthly',starts_on:`${year}-01-01`,ends_before:`${year+1}-01-01`,
 document_hash,storage_path:`${targetCompany}/${tableId}/${version}/${document_hash}.pdf`,
 source_url:'https://example.test/fixture.pdf',publisher:'Fixture only',file_name:'fixture.pdf',...overrides};
}
async function actor(actorId,role='authenticated',allowed=true) {
 await db.exec('reset role');
 await db.query("select set_config('test.actor',$1,false),set_config('test.account_allowed',$2,false)",[actorId,String(allowed)]);
 await db.exec(`set role ${role}`);
}
async function register(tableId,expectedVersion,value,confirmed=true,targetCompany=company) {
 return (await db.query('select public.register_company_income_tax_table($1,$2,$3,$4::jsonb,$5) as result',
 [targetCompany,tableId,expectedVersion,JSON.stringify(value),confirmed])).rows[0].result;
}
async function read(date='2030-01-01',kind='monthly',targetCompany=company) {
 return (await db.query('select public.read_company_income_tax_tables($1,$2,$3) as result',[targetCompany,date,kind])).rows[0].result;
}
async function verify(tableId,version,value,{rules=false,hash=value.document_hash,path=value.storage_path}={}) {
 await db.exec('reset role');
 await db.query(`insert into income_tax_private.verifications(company_id,table_id,metadata_version,document_hash,storage_path,official_verified_by,official_verified_at,verification_evidence,calculation_rules_hash,calculation_rules_version,calculation_verified_by,calculation_verified_at)
 values($1,$2,$3,$4,$5,$6,now(),'isolated fixture official verification',$7,$8,$9,case when $9::uuid is not null then now() else null end)`,
 [company,tableId,version,hash,path,owner,rules?'b'.repeat(64):null,rules?'fixture-artifact-v1':null,rules?owner:null]);
 await actor(admin);
}
try {
 await db.exec(fs.readFileSync('supabase/tests/company_income_tax_table_registry_bootstrap.sql','utf8'));
 await db.exec(fs.readFileSync('supabase/migrations/20261009155006_company_income_tax_table_registry.sql','utf8'));
 const security=await db.query(`select c.relname,c.relrowsecurity,has_table_privilege('authenticated',c.oid,'SELECT,INSERT,UPDATE,DELETE') as granted
 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='income_tax_private' and c.relkind='r'`);
 assert.equal(security.rows.length,3);
 for(const row of security.rows) {assert.equal(row.relrowsecurity,true);assert.equal(row.granted,false);}
 for(const actorId of [worker,otherAdmin,'']) {
  await actor(actorId);await assert.rejects(read(),/admin access denied/);
  await assert.rejects(register(id,0,metadata(id,2030)),/admin access denied/);
 }
 await actor(admin,'authenticated',false);await assert.rejects(read(),/admin access denied/);
 await assert.rejects(register(id,0,metadata(id,2030)),/admin access denied/);
 await actor(owner,'anon');await assert.rejects(read(),/permission denied/);
 await assert.rejects(register(id,0,metadata(id,2030)),/permission denied/);
 await actor(owner);
 await assert.rejects(db.query('select * from income_tax_private.documents'),/permission denied/);
 await assert.rejects(db.query('insert into income_tax_private.verifications(company_id) values($1)',[company]),/permission denied/);
 await assert.rejects(register(id,0,metadata(id,2030),false),/confirmation required/);
 for(const invalid of [
  {official_document_verified:true}, {common_data_approved:true}, {kind:'income_tax_percent'},
  {calendar_year:2030.5}, {starts_on:'2030-02-29'}, {starts_on:'2030-01-01T00:00:00Z'},
  {ends_before:'2032-01-01'}, {document_hash:'fake'}, {storage_path:'other-company/path.pdf'},
  {file_name:'../fixture.pdf'}, {publisher:'x'.repeat(201)},
 ]) await assert.rejects(register(id,0,metadata(id,2030,1,company,invalid)));
 const initial=await register(id,0,metadata(id,2030));
 assert.equal(initial.version,1);assert.equal(initial.official_document_verified,false);
 assert.equal(initial.calculation_rules_verified,false);assert.equal(initial.common_data_approved,false);
 let state=await read();assert.equal(state.selected,null,'upload metadata cannot select tax rules');
 await assert.rejects(register(id,0,metadata(id,2030)),/version conflict/);
 await assert.rejects(register(id,1,metadata(id,2030,2),true,other),/admin access denied/);
 await assert.rejects(register(distinct,0,metadata(distinct,2030,1,company,{starts_on:'2030-06-01'})),/schedule overlap/);
 assert.deepEqual(await read(),state,'failed saves must preserve metadata and history');
 await verify(id,1,metadata(id,2030));
 state=await read();assert.equal(state.tables[0].official_document_verified,true);
 assert.equal(state.tables[0].calculation_rules_verified,false);assert.equal(state.selected,null,'official PDF alone is not rules');
 await db.exec('reset role');
 await db.query(`update income_tax_private.verifications set calculation_rules_hash=$1,calculation_rules_version='fixture-v1',calculation_verified_by=$2,calculation_verified_at=now() where company_id=$3 and table_id=$4`,['b'.repeat(64),owner,company,id]);
 await actor(admin);
 state=await read('2030-12-31');assert.equal(state.selected.table_id,id);
 assert.equal(state.selected.common_data_approved,false);
 // Annual/category identity cannot silently erase an old ready schedule.
 const beforeIdentityChange=await read('2030-12-31');
 await assert.rejects(register(id,1,metadata(id,2031,2)),/calendar year and kind are immutable/);
 assert.deepEqual(await read('2030-12-31'),beforeIdentityChange,'new-year reuse must preserve documents, verification state and all audit entries');
 await assert.rejects(register(id,1,metadata(id,2030,2,company,{kind:'daily'})),/calendar year and kind are immutable/);
 assert.deepEqual(await read('2030-12-31'),beforeIdentityChange,'kind reuse must preserve documents, verification state and all audit entries');
 assert.equal((await read('2030-12-31')).selected.table_id,id,'original year must remain selectable');
 await register(nextId,0,metadata(nextId,2031));
 assert.equal((await read('2031-01-01')).selected,null,'unverified future year must not fallback to expired old year');
 await verify(nextId,1,metadata(nextId,2031),{rules:true});
 assert.equal((await read('2031-01-01')).selected.table_id,nextId,'new year selects on exact civil boundary');
 assert.equal((await read('2030-12-31')).selected.table_id,id,'old year remains available');
 assert.equal((await read('2032-01-01')).selected,null,'expired tables never fallback');
 assert.equal((await read('2031-01-01','daily')).selected,null,'table types are independent');
 await assert.rejects(read('2031-01-01T00:00:00Z'),/civil payroll date/);
 await assert.rejects(read('2031-02-29'));
 const revised=await register(id,1,metadata(id,2030,2));
 assert.equal(revised.official_document_verified,false,'metadata version change invalidates old verification');
 assert.equal((await read('2030-05-01')).selected,null);
 // Even trusted rows must bind to the exact current hash/path/version.
 await verify(id,2,metadata(id,2030,2),{rules:true,hash:'c'.repeat(64)});
 assert.equal((await read('2030-05-01')).selected,null,'mismatched verified identity cannot select');
 await db.exec('reset role');
 await db.query('update income_tax_private.verifications set document_hash=$1,storage_path=$2 where company_id=$3 and table_id=$4 and metadata_version=2',['a'.repeat(64),'wrong/path',company,id]);
 await actor(admin);assert.equal((await read('2030-05-01')).selected,null,'mismatched path cannot select');
 state=await read();
 const registration=state.history.find(x=>x.event_type==='registration'&&x.table_id===id&&x.version===2);
 assert.deepEqual(registration.before_value,metadata(id,2030));assert.deepEqual(registration.after_value,metadata(id,2030,2));
 assert.equal(registration.actor_id,admin);assert.ok(registration.changed_at);
 assert.ok(state.history.some(x=>x.event_type==='verification'));
 // Adjacent periods with distinct IDs and same kind are allowed.
 await register(distinct,0,metadata(distinct,2032,1,company,{ends_before:'2032-07-01'}));
 const adjacent='30000000-0000-0000-0000-000000000004';
 await register(adjacent,0,metadata(adjacent,2032,1,company,{starts_on:'2032-07-01'}));
 await db.exec('reset role');
 await db.exec(`create function income_tax_private.fixture_audit_fail() returns trigger language plpgsql as $$ begin raise exception 'synthetic income tax audit unavailable'; end $$;
 create trigger fixture_audit_fail before insert on income_tax_private.history for each row execute function income_tax_private.fixture_audit_fail()`);
 await actor(admin);const beforeFailure=await read();
 await assert.rejects(register(id,2,metadata(id,2030,3)),/synthetic income tax audit unavailable/);
 assert.deepEqual(await read(),beforeFailure,'audit failure rolls back version and document identity');
 await db.exec('reset role');await db.exec('drop trigger fixture_audit_fail on income_tax_private.history');
 await actor(otherAdmin);await register(id,0,metadata(id,2030,1,other),true,other);
 const otherState=await read('2030-01-01','monthly',other);
 await db.exec('reset role');
 const oldHistory=(await db.query('select * from income_tax_private.history where company_id=$1 order by event_id',[company])).rows;
 await db.query('delete from public.companies where id=$1',[company]);
 for(const table of ['documents','verifications']) assert.equal((await db.query(`select count(*)::int as n from income_tax_private.${table} where company_id=$1`,[company])).rows[0].n,0);
 const retained=(await db.query('select * from income_tax_private.history where company_id=$1 order by event_id',[company])).rows;
 assert.deepEqual(retained.slice(0,oldHistory.length),oldHistory,'existing history must survive company deletion');
 await actor(admin);await assert.rejects(read(),/admin access denied/);
 await assert.rejects(register(id,0,metadata(id,2030)),/admin access denied/);
 await assert.rejects(db.query('select * from income_tax_private.history'),/permission denied/);
 await actor(otherAdmin);assert.deepEqual(await read('2030-01-01','monthly',other),otherState);
 console.log('PASS exact staged income tax registry: tenant/admin/anon guards, metadata identity, version/audit rollback, private verification, overlap/adjacency, civil new-year selection, expired nofallback, deletion retention');
} finally {await db.close();}
