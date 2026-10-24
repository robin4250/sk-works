// Native PG17 only, reused application fixture and exact annual source.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {randomUUID} from 'node:crypto';
import {setupPayrollScopeFixture} from './payroll_scope_fixture_setup.mjs';

const raw=process.env.SKO_RESIDENT_ANNUAL_FIXTURE_URL??'';
const url=new URL(raw);
assert.ok(['127.0.0.1','localhost'].includes(url.hostname));
assert.equal(url.pathname,'/sko_resident_annual_fixture');
assert.equal(url.username,'postgres');assert.equal(url.password,'fixture-only');
assert.equal(url.search,'');assert.equal(url.hash,'');
const pg=(await import(process.argv[2])).default;
pg.types.setTypeParser(20,Number);pg.types.setTypeParser(1700,Number);
const client=new pg.Client({connectionString:raw});await client.connect();
const db={query:(...args)=>client.query(...args),exec:sql=>client.query(sql)};
const root=process.cwd(),temp=fs.mkdtempSync(path.join(os.tmpdir(),'sko-resident-annual-deploy-'));
fs.chmodSync(temp,0o700);
let assertions=0;
const ok=x=>{assert.equal(x,true);assertions++;};
function artifact(mode,before,after){
 const out=path.join(temp,`${mode}-${randomUUID()}.sql`);
 const args=['tool/security/prepare_resident_annual_deployment_review.py','--source-root',root,'--output',out];
 for(const[key,value]of[['before',before],['after',after]])if(value!=null){const p=path.join(temp,`${key}-${randomUUID()}.json`);fs.writeFileSync(p,JSON.stringify(value),{mode:0o600,flag:'wx'});args.push(`--${key}`,p);}
 args.push(mode);const result=spawnSync('python3',args,{cwd:root,encoding:'utf8'});
 if(result.status!==0)throw Error(`offline annual ${mode} generation failed`);
 return fs.readFileSync(out,'utf8');
}
const observeSql=artifact('observer');
async function observe(){
 await db.exec('reset role;begin;');
 try{await db.exec(observeSql.slice(0,observeSql.lastIndexOf("select current_setting('sko.resident_annual_observation')")));
  const result=(await db.query("select current_setting('sko.resident_annual_observation')::jsonb observation")).rows[0].observation;
  await db.exec('rollback;');return result;
 }catch(e){await db.exec('rollback;');throw e;}
}
async function rejected(sql,args){let failed=false;try{await db.query(sql,args);}catch{failed=true;await db.exec('rollback;');}ok(failed);}
const cid='10000000-0000-0000-0000-000000000001',wid='40000000-0000-0000-0000-000000000001';
const owner='00000000-0000-0000-0000-000000000001',viewer='00000000-0000-0000-0000-000000000003';
async function actor(id){await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated');}
try{
 const version=Number((await db.query("select current_setting('server_version_num') n")).rows[0].n);ok(version>=170000&&version<180000);
 ok((await db.query("select count(*)::int n from pg_tables where schemaname='public'")).rows[0].n===0);
 await setupPayrollScopeFixture(db);
 await db.exec(fs.readFileSync('supabase/migrations/20261009171504_payroll_refresh_scope_order.sql','utf8'));
 await db.exec('reset role;create role service_role nologin;');
 const before=await observe(),install=artifact('install',before);
 await db.exec('begin;');await db.query("update public.workers set name=name||'-stale' where id=$1",[wid]);
 await rejected(install);assert.deepEqual(await observe(),before);assertions++;
 ok((await db.query("select to_regnamespace('resident_tax_annual_private') is null v")).rows[0].v);
 await rejected(install.replace(/commit;\s*$/i,"do $$begin raise exception 'fixture late postflight';end$$;commit;"));
 assert.deepEqual(await observe(),before);assertions++;
 await db.exec(install);
 const after=await observe(),restore=artifact('unused-restore',before,after);
 ok(Object.keys(after.routines).length===22&&Object.keys(after.relations).length===12);
 ok(Object.values(after.data).every(x=>typeof x.count==='number'));
 for(const name of['confirmations','batches','changes','undos'])ok(after.data[`resident_tax_annual_private.${name}`].count===0);
 await db.exec(restore);assert.deepEqual(await observe(),before);assertions++;
 await db.exec(install);
 ok((await db.query("select not has_function_privilege('anon','public.read_company_resident_tax_annual(uuid,integer,uuid)','execute') v")).rows[0].v);
 await actor(viewer);
 const view=(await db.query('select public.read_company_resident_tax_annual($1,2026,null) v',[cid])).rows[0].v;
 ok(view.can_edit===false);
 await rejected('select public.save_company_resident_tax_annual($1,2026,$2,$3,$4)',[cid,view.snapshot,[],randomUUID()]);
 await actor(owner);
 await rejected('select public.read_company_resident_tax_annual($1,2026,null)',['ffffffff-ffff-ffff-ffff-ffffffffffff']);
 await actor(owner);
 const state=(await db.query('select public.read_company_resident_tax_annual($1,2026,null) v',[cid])).rows[0].v;
 ok(state.can_edit===true&&state.workers.length>0);
 const entries=state.workers.map(w=>({worker_id:w.worker_id,amounts:w.amounts,confirmed:true,excluded:false,reason:null}));
 const request=randomUUID();
 const saved=(await db.query('select public.save_company_resident_tax_annual($1,2026,$2::jsonb,$3::jsonb,$4) v',[cid,JSON.stringify(state.snapshot),JSON.stringify(entries),request])).rows[0].v;
 const retry=(await db.query('select public.save_company_resident_tax_annual($1,2026,$2::jsonb,$3::jsonb,$4) v',[cid,JSON.stringify(state.snapshot),JSON.stringify(entries),request])).rows[0].v;
 assert.deepEqual(retry,saved);assertions++;
 await db.exec('reset role;');await rejected(restore);
 const used=await observe();ok(used.data['resident_tax_annual_private.batches'].count===1);
 for(const[name,value]of Object.entries(before.data)){assert.deepEqual(used.data[name],value);assertions++;}
 console.log(JSON.stringify({phase:'passed',assertions,native_postgres:17,synthetic:true,production_connected:false,
  proof:['strict stale checkpoint rejection','late installation rollback','exact unused removal equality','new schema/tables empty',
  'anonymous/viewer denial','owner explicit same-value confirmation','durable retry','used removal refusal','financial originals unchanged']}));
}finally{await db.exec('rollback;reset role;').catch(()=>{});await client.end();fs.rmSync(temp,{recursive:true,force:true});}
