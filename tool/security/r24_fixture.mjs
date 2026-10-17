import assert from 'node:assert/strict';import fs from 'node:fs/promises';
import {fileURLToPath,pathToFileURL} from 'node:url';import {createHash,createHmac,randomUUID} from 'node:crypto';
import {r20Setup,r20Verify,r20Http,r20Restore} from './r20_fixture.mjs';
const catalog24=JSON.parse(await fs.readFile(new URL('./r24_catalog.json',import.meta.url),'utf8'));
const helper24=catalog24.functions.find(x=>x.proname==='ensure_invoice_approval_rows');
const trigger24=catalog24.functions.find(x=>x.proname==='invoice_approval_rows_trigger');
let original24;let checks24=0;
const metadata24=async db=>(await db.query(`select p.oid::text,pg_get_functiondef(p.oid) definition,pg_get_userbyid(p.proowner) owner,p.proacl::text acl,p.proconfig::text config,p.prosecdef from pg_proc p where p.oid='private.ensure_invoice_approval_rows(uuid)'::regprocedure`)).rows;
async function r24Setup(db){await db.exec(helper24.definition);original24=await metadata24(db);assert.equal(original24[0].acl,helper24.acl);checks24++;}
async function r24Verify(db,id){
 await db.exec('begin');try{await db.query('delete from public.invoice_approvals where invoice_id=$1',[id(21)]);await actor23(db,id(2),()=>db.query('select private.ensure_invoice_approval_rows($1)',[id(21)]));assert.equal((await db.query('select count(*)::int n from public.invoice_approvals where invoice_id=$1',[id(21)])).rows[0].n,1);checks24++;}finally{await db.exec('rollback');}
 await db.exec(await fs.readFile(new URL('./r24_candidate.sql.review-only',import.meta.url),'utf8'));
 for(const actor of [id(1),id(2)])for(const historical of [false,true]){
 await db.exec('begin');try{
 if(historical){await db.query('delete from private.line_invoice_submissions where invoice_id=$1',[id(21)]);await db.query('insert into private.line_historical_invoice_links values($1,$2)',[id(21),id(10)]);}
 await db.query('delete from public.invoice_approvals where invoice_id=$1',[id(21)]);await actor23(db,actor,()=>db.query('select private.ensure_invoice_approval_rows($1)',[id(21)]));assert.equal((await db.query('select count(*)::int n from public.invoice_approvals where invoice_id=$1',[id(21)])).rows[0].n,0);checks24++;
 await db.query('delete from public.invoice_approvals where invoice_id=$1',[id(20)]);await actor23(db,actor,()=>db.query('select private.ensure_invoice_approval_rows($1)',[id(20)]));assert.deepEqual((await db.query('select approver_user_id,position,status from public.invoice_approvals where invoice_id=$1',[id(20)])).rows,[{approver_user_id:id(1),position:1,status:'pending'}]);checks24++;
 }finally{await db.exec('rollback');}}
 // Demonstrate the still-open ordering window with the actual trigger body.
 await db.exec('begin');try{
 await db.exec(trigger24.definition);await db.exec(catalog24.trigger);
 await db.query('update public.invoice_approvers set user_id=$1',[id(2)]);
 await db.query("insert into public.invoices(id,company_id,body,billing_period_end) values($1,$2,'synthetic-before-lineage','2026-09-30')",[id(88),id(10)]);
 await db.query('insert into private.line_invoice_submissions values($1,$2)',[id(88),id(10)]);
 assert.equal((await db.query('select count(*)::int n from public.invoice_approvals where invoice_id=$1 and approver_user_id=$2',[id(88),id(2)])).rows[0].n,1);checks24++;
 assert.equal((await db.query('select count(*)::int n from public.app_notifications where action_id=$1 and recipient_user_id=$2',[id(88),id(2)])).rows[0].n,1);checks24++;
 }finally{await db.exec('rollback');}
 for(const row of catalog24.creationOrder){const invoice=row.definition.indexOf('insert into public.invoices(');const lineage=row.definition.indexOf(row.proname==='create_line_invoices'?'insert into private.line_invoice_submissions':'insert into private.line_historical_invoice_links');assert.ok(invoice>0&&lineage>invoice);checks24++;}
 const after=await metadata24(db);for(const key of ['oid','owner','acl','config','prosecdef']){assert.equal(after[0][key],original24[0][key]);checks24++;}
}
async function r24Http(db,id,token,origin){
 // Fixture-only definer probe; the real helper stays in the private schema.
 await db.exec(`create function public.r24_probe(p_id uuid) returns void language sql security definer set search_path='' as $$select private.ensure_invoice_approval_rows(p_id)$$;revoke all on function public.r24_probe(uuid) from public,anon;grant execute on function public.r24_probe(uuid) to authenticated;notify pgrst,'reload schema';`);
 const before=await snapshot23(db);
 for(const actor of [id(1),id(2)]){try{await db.query('delete from public.invoice_approvals where invoice_id=$1',[id(21)]);const r=await fetch(new URL('/rpc/r24_probe',origin),{method:'POST',headers:{Authorization:'Bearer '+token(actor),'Content-Type':'application/json'},body:JSON.stringify({p_id:id(21)}),redirect:'error'});assert.ok([200,204].includes(r.status));assert.equal((await db.query('select count(*)::int n from public.invoice_approvals where invoice_id=$1',[id(21)])).rows[0].n,0);checks24+=2;}finally{await db.exec('delete from public.invoice_approvals');await db.query('insert into public.invoice_approvals select * from jsonb_populate_recordset(null::public.invoice_approvals,$1::jsonb)',[JSON.stringify(before.invoice_approvals)]);}}
 assert.deepEqual(await snapshot23(db),before);checks24++;
}
async function r24Restore(db){await db.exec(helper24.definition);assert.deepEqual(await metadata24(db),original24);checks24++;await db.exec(helper24.definition.replace('AS $function$','AS $function$ -- fixture drift\n'));const drifted=await metadata24(db);await assert.rejects(db.exec(await fs.readFile(new URL('./r24_candidate.sql.review-only',import.meta.url),'utf8')),e=>e.code==='55000');checks24++;await db.exec('rollback');assert.deepEqual(await metadata24(db),drifted);checks24++;await db.exec(helper24.definition);assert.deepEqual(await metadata24(db),original24);checks24++;console.log(`PASS ${checks24} R24 known-lineage lazy sync checks; actual trigger creation-before-lineage leak reproduced, not fixed.`);}
const source24=await fs.readFile(new URL('./r23_fixture.mjs',import.meta.url),'utf8');const source22=await fs.readFile(new URL('./r22_fixture.mjs',import.meta.url),'utf8');const source21=await fs.readFile(new URL('./r21_fixture.mjs',import.meta.url),'utf8');const source19=await fs.readFile(new URL('./r19_fixture.mjs',import.meta.url),'utf8');
const self24=await fs.readFile(fileURLToPath(import.meta.url),'utf8');
let adapted24=self24.slice(0,self24.indexOf('const source24='))+'\n'+source24.slice(0,source24.indexOf('const source23=')).replace(/^import .*;\n/gm,'')+'\n'+source22.slice(0,source22.indexOf('const source22=')).replace(/^import .*;\n/gm,'')+'\n'+source21.slice(0,source21.indexOf("if(fileURLToPath(import.meta.url)===process.argv[1])")).replace(/^import .*;\n/gm,'')+'\n'+source19.replace(/^import .*;\n/gm,'');
for(const [anchor,replacement]of [
 ['  const before=await Promise.all','  await r21Setup(db,id);await r22Setup(db,id);await r23Setup(db,id);await r24Setup(db);\n  const before=await Promise.all'],
 ['  const helpers=(await db.query','  await r21Verify(db,id);await r22Verify(db,id);await r23Verify(db,id);await r24Verify(db,id);\n  const helpers=(await db.query'],
 ["    console.log('VERIFIED actual PG17","    await r21Http(db,id,token,origin);await r22Http(db,id,token,origin);await r23Http(db,id,token,origin);await r24Http(db,id,token,origin);\n    console.log('VERIFIED actual PG17"],
 ['  for(let i=0;i<tables.length;i++){','  await r24Restore(db);await r23Restore(db);await r22Restore(db);await r21Restore(db);\n  for(let i=0;i<tables.length;i++){']
 ]){assert.equal(adapted24.split(anchor).length,2);adapted24=adapted24.replace(anchor,replacement);}
const temp24=new URL(`./.r24-${randomUUID()}.mjs`,import.meta.url);try{await fs.writeFile(temp24,adapted24,{mode:0o600,flag:'wx'});await import(temp24.href);}finally{await fs.unlink(temp24).catch(()=>{});}
