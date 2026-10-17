import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {createHash,createHmac,randomUUID} from 'node:crypto';
import {r20Setup,r20Verify,r20Http,r20Restore} from './r20_fixture.mjs';
const catalog23=JSON.parse(await fs.readFile(new URL('./r23_catalog.json',import.meta.url),'utf8'));
const signature23='public.set_invoice_approvers(uuid[])';let original23;let checks23=0;
const tables23=['invoices','invoice_approvers','invoice_approvals','invoice_approval_audit'];
const metadata23=async db=>(await db.query(`select p.oid::text,pg_get_functiondef(p.oid) definition,pg_get_userbyid(p.proowner) owner,p.proacl::text acl,p.proconfig::text config,p.prosecdef from pg_proc p where p.oid=$1::regprocedure`,[signature23])).rows;
const actor23=async(db,actor,fn)=>{await db.exec('set role authenticated');try{await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:actor})]);return await fn();}finally{await db.exec('reset role').catch(()=>{});}};
const snapshot23=async db=>{const out={};for(const t of tables23)out[t]=(await db.query(`select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),'[]') rows from public.${t} x`)).rows[0].rows;return out;};
const protected23=(s,id)=>({invoices:s.invoices.filter(r=>[id(21),id(24),id(25),id(22)].includes(r.id)),approvals:s.invoice_approvals.filter(r=>[id(21),id(24),id(25),id(22)].includes(r.invoice_id)),audit:s.invoice_approval_audit.filter(r=>[id(21),id(24),id(25),id(22)].includes(r.invoice_id))});
async function r23Setup(db,id){
 await db.exec(`create table public.invoice_approvers(company_id uuid,position integer,user_id uuid,created_by uuid);
 insert into public.invoice_approvers values('${id(10)}',1,'${id(1)}','${id(1)}');
 alter table public.invoice_approvals add unique(invoice_id,approver_user_id);
 alter table public.invoice_approval_audit alter id set default gen_random_uuid();
 update public.invoices set approval_finalized_at='2026-10-01';
`);
 await db.exec(catalog23[0].definition);await db.exec(`revoke all on function ${signature23} from public,anon;grant execute on function ${signature23} to authenticated,service_role`);original23=await metadata23(db);assert.equal(original23[0].acl,catalog23[0].acl);checks23++;
}
async function verifyOutcome23(db,id,before,actor){
 const after=await snapshot23(db);assert.deepEqual(protected23(after,id),protected23(before,id));checks23++;
 assert.deepEqual(after.invoice_approvers.filter(r=>r.company_id===id(10)).map(r=>r.user_id),[actor]);checks23++;
 const ordinary=after.invoices.find(r=>r.id===id(20));assert.equal(ordinary.approval_finalized_at,null);checks23++;
 assert.deepEqual(after.invoice_approvals.filter(r=>r.invoice_id===id(20)).map(r=>({user:r.approver_user_id,status:r.status})),[{user:actor,status:'pending'}]);checks23++;
 assert.equal(after.invoice_approval_audit.filter(r=>r.invoice_id===id(20)&&r.action==='approvers_changed').length,1);checks23++;
}
async function r23Verify(db,id){
 const before=await snapshot23(db);
 // Reproduce original cross-boundary bulk sync, including linked audit writes.
 await db.exec('begin');try{await actor23(db,id(2),()=>db.query('select public.set_invoice_approvers($1)',[[id(2)]]));const after=await snapshot23(db);assert.notDeepEqual(protected23(after,id),protected23(before,id));checks23++;}finally{await db.exec('rollback');}
 await db.exec(await fs.readFile(new URL('./r23_candidate.sql.review-only',import.meta.url),'utf8'));
 for(const actor of [id(2),id(1)])for(const historical of [false,true]){await db.exec('begin');try{if(historical){await db.query('delete from private.line_invoice_submissions where invoice_id=$1',[id(21)]);await db.query('insert into private.line_historical_invoice_links values($1,$2)',[id(21),id(10)]);}if(actor===id(1))await db.query('update public.invoice_approvers set user_id=$1',[id(2)]);await actor23(db,actor,()=>db.query('select public.set_invoice_approvers($1)',[[actor]]));await verifyOutcome23(db,id,before,actor);}finally{await db.exec('rollback');}assert.deepEqual(await snapshot23(db),before);checks23++;}
 for(const ids of [[],[id(2),id(2)],[id(5)]]){await actor23(db,id(2),()=>assert.rejects(db.query('select public.set_invoice_approvers($1)',[ids])));assert.deepEqual(await snapshot23(db),before);checks23+=2;}
 await actor23(db,id(5),()=>assert.rejects(db.query('select public.set_invoice_approvers($1)',[[id(2)]]),/registered company user/));assert.deepEqual(await snapshot23(db),before);checks23+=2;
 const after=await metadata23(db);for(const key of ['oid','owner','acl','config','prosecdef']){assert.equal(after[0][key],original23[0][key]);checks23++;}
 // All five exact anchors are replaced, no company configuration replacement.
 assert.equal((after[0].definition.match(/not exists\(select 1 from private.line_invoice_submissions/g)||[]).length,5);checks23++;
}
async function r23Http(db,id,token,origin){
 await db.exec("notify pgrst, 'reload schema'");const before=await snapshot23(db);
 for(const actor of [id(2),id(1)]){
 try{
 if(actor===id(1))await db.query('update public.invoice_approvers set user_id=$1',[id(2)]);
 const r=await fetch(new URL('/rpc/set_invoice_approvers',origin),{method:'POST',redirect:'error',headers:{Authorization:'Bearer '+token(actor),'Content-Type':'application/json'},body:JSON.stringify({p_user_ids:[actor]})});assert.ok([200,204].includes(r.status));checks23++;await verifyOutcome23(db,id,before,actor);
 }finally{
 // Disposable owner-only fixture cleanup, never a production restore command.
 for(const t of tables23){await db.exec(`delete from public.${t}`);await db.query(`insert into public.${t} select * from jsonb_populate_recordset(null::public.${t},$1::jsonb)`,[JSON.stringify(before[t])]);}
 }assert.deepEqual(await snapshot23(db),before);checks23++;
 }
}
async function r23Restore(db){
 await db.exec(catalog23[0].definition);assert.deepEqual(await metadata23(db),original23);checks23++;
 await db.exec(catalog23[0].definition.replace('AS $function$','AS $function$ -- fixture drift\n'));const drifted=await metadata23(db);await assert.rejects(db.exec(await fs.readFile(new URL('./r23_candidate.sql.review-only',import.meta.url),'utf8')),e=>e.code==='55000');checks23++;await db.exec('rollback');assert.deepEqual(await metadata23(db),drifted);checks23++;
 await db.exec(catalog23[0].definition);assert.deepEqual(await metadata23(db),original23);checks23++;
 console.log(`PASS ${checks23} R23 five-anchor bulk synchronization guards; ordinary settings retained; other sync paths remain blockers.`);
}
const source23=await fs.readFile(new URL('./r22_fixture.mjs',import.meta.url),'utf8');
const source21=await fs.readFile(new URL('./r21_fixture.mjs',import.meta.url),'utf8');
const source19=await fs.readFile(new URL('./r19_fixture.mjs',import.meta.url),'utf8');
assert.equal(createHash('sha256').update(source19).digest('hex'),'4a07279de9ee5e4d72075efa994737f419d28a7fad5f6d12901a1447dc611586');
const self23=await fs.readFile(fileURLToPath(import.meta.url),'utf8');
let adapted23=self23.slice(0,self23.indexOf('const source23='))+'\n'+source23.slice(0,source23.indexOf('const source22=')).replace(/^import .*;\n/gm,'')+'\n'+source21.slice(0,source21.indexOf("if(fileURLToPath(import.meta.url)===process.argv[1])")).replace(/^import .*;\n/gm,'')+'\n'+source19.replace(/^import .*;\n/gm,'');
for(const [anchor,replacement]of [
 ['  const before=await Promise.all','  await r21Setup(db,id);await r22Setup(db,id);await r23Setup(db,id);\n  const before=await Promise.all'],
 ['  const helpers=(await db.query','  await r21Verify(db,id);await r22Verify(db,id);await r23Verify(db,id);\n  const helpers=(await db.query'],
 ["    console.log('VERIFIED actual PG17","    await r21Http(db,id,token,origin);await r22Http(db,id,token,origin);await r23Http(db,id,token,origin);\n    console.log('VERIFIED actual PG17"],
 ['  for(let i=0;i<tables.length;i++){','  await r23Restore(db);await r22Restore(db);await r21Restore(db);\n  for(let i=0;i<tables.length;i++){']
 ]){assert.equal(adapted23.split(anchor).length,2);adapted23=adapted23.replace(anchor,replacement);}
const temp23=new URL(`./.r23-${randomUUID()}.mjs`,import.meta.url);try{await fs.writeFile(temp23,adapted23,{mode:0o600,flag:'wx'});await import(temp23.href);}finally{await fs.unlink(temp23).catch(()=>{});}
