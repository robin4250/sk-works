import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
const pg=(await import(process.argv[2]??'pg')).default;
const url=new URL(process.env.SKO_BANK_FIXTURE_URL??'');
if(!['127.0.0.1','localhost','[::1]'].includes(url.hostname)||url.pathname!='/sko_own_bank_fixture')throw Error('Disposable loopback bank fixture only');
const clients=[];
async function connect(){const c=new pg.Client({connectionString:url.href});await c.connect();clients.push(c);return c;}
const a='10000000-0000-0000-0000-000000000001',b='10000000-0000-0000-0000-000000000002';
const company='30000000-0000-0000-0000-000000000001',otherCompany='30000000-0000-0000-0000-000000000002';
const w='40000000-0000-0000-0000-000000000001',raceWorker='40000000-0000-0000-0000-000000000002',requirement='50000000-0000-0000-0000-000000000001';
const sql='insert into public.worker_private_bank_accounts(worker_id,company_id,bank_name,branch_name,account_type,account_number,account_holder) values($1,$2,$3,$4,$5,$6,$7) returning worker_id,company_id,updated_at';
const values=(worker=w,companyId=company,bank='SYNTHETIC BANK',number='0000001',type='普通')=>[worker,companyId,bank,'SYNTHETIC BRANCH',type,number,'SYNTHETIC HOLDER'];
async function actor(c,id){await c.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:id,role:'authenticated'})]);await c.query('set role authenticated');await c.query("set statement_timeout='5s'");}
try {
 const admin=await connect();assert.match((await admin.query('show server_version')).rows[0].server_version,/^17\./);
 await admin.query(await fs.readFile(new URL('./own_bank_account_fixture/schema.sql',import.meta.url),'utf8'));
 await admin.query('insert into public.companies values($1),($2)',[company,otherCompany]);
 await admin.query('insert into public.workers values($1,$3,$4),($2,$3,$4)',[w,raceWorker,company,a]);
 await admin.query("insert into public.document_requirements values($1,$2,'銀行口座情報',true)",[requirement,company]);
 await admin.query("insert into public.worker_document_statuses values($1,$2,$3,'verified',true,$4,now(),'SYNTHETIC-ORIGINAL-PATH','SYNTHETIC-ORIGINAL-NOTE')",[company,w,requirement,a]);
 const self=await connect(),foreign=await connect(),race1=await connect(),race2=await connect();
 await actor(self,a);await actor(foreign,b);await actor(race1,a);await actor(race2,a);
 await assert.rejects(foreign.query(sql,values()),e=>['P0001','42501'].includes(e.code));
 await assert.rejects(self.query(sql,values(w,otherCompany)),e=>['P0001','42501'].includes(e.code));
 for(const [number,type] of [['123456','普通'],['12345678','普通'],['００００００１','普通'],['0000001','その他']]) {
  await assert.rejects(self.query(sql,values(w,company,'SYNTHETIC BANK',number,type)),e=>e.code==='23514');
 }
 const row=(await self.query(sql,values())).rows[0];assert.equal(row.worker_id,w);assert.equal(row.company_id,company);assert.equal(Object.keys(row).length,3);
 assert.equal((await foreign.query('select worker_id from public.worker_private_bank_accounts')).rowCount,0);
 const saved=(await admin.query('select md5(row_to_json(b)::text) as digest from public.worker_private_bank_accounts b where worker_id=$1',[w])).rows[0].digest;
 await assert.rejects(self.query(sql,values(w,company,'SYNTHETIC DUPLICATE')),e=>e.code==='23505');
 assert.equal((await admin.query('select md5(row_to_json(b)::text) as digest from public.worker_private_bank_accounts b where worker_id=$1',[w])).rows[0].digest,saved);
 const status=(await admin.query('select status,attachment_path,notes from public.worker_document_statuses where worker_id=$1',[w])).rows[0];
 assert.deepEqual(status,{status:'submitted',attachment_path:'SYNTHETIC-ORIGINAL-PATH',notes:'SYNTHETIC-ORIGINAL-NOTE'});
 const race=await Promise.allSettled([race1.query(sql,values(raceWorker,company,'SYNTHETIC RACE A')),race2.query(sql,values(raceWorker,company,'SYNTHETIC RACE B'))]);
 assert.equal(race.filter(r=>r.status==='fulfilled').length,1);assert.equal(race.filter(r=>r.status==='rejected'&&r.reason.code==='23505').length,1);
 assert.equal((await admin.query('select count(*)::int n from public.worker_private_bank_accounts where worker_id=$1',[raceWorker])).rows[0].n,1);
 await admin.query('insert into private.account_deletion_access_restrictions values($1)',[a]);
 assert.equal((await self.query('select worker_id from public.worker_private_bank_accounts')).rowCount,0);
 console.log(JSON.stringify({pass:true,own_scope:true,wrong_company_denied:true,seven_digit_constraints:true,metadata_only:true,duplicate_preserved:true,original_attachments_preserved:true,concurrent_insert_single_winner:true,deletion_guard:true}));
} finally {await Promise.allSettled(clients.map(c=>c.end()));}
