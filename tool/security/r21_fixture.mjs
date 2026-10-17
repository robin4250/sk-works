import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createHash, createHmac, randomUUID } from 'node:crypto';
import {r20Setup,r20Verify,r20Http,r20Restore} from './r20_fixture.mjs';
const catalog21=JSON.parse(await fs.readFile(new URL('./r21_catalog.json',import.meta.url),'utf8'));
const signatures21=['public.approve_invoice(uuid)','public.cancel_invoice_approval(uuid)','public.set_invoice_stamp_display_date(uuid,uuid,date)'];
const writeTables=['invoices','communication_groups','communication_notes','communication_albums','communication_album_items'];
let original21;let checks21=0;
const metadata21=async db=>(await db.query(`select p.oid::text,pg_get_functiondef(p.oid) definition,
pg_get_userbyid(p.proowner) owner,p.proacl::text acl,p.proconfig::text config from pg_proc p
where p.oid=any($1::regprocedure[]) order by p.oid`,[signatures21])).rows;
const actor21=async(db,actor,fn)=>{await db.exec('set role authenticated');try{
await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:actor})]);return await fn();
}finally{await db.exec('reset role').catch(()=>{});}};

async function r21Setup(db,id){
 await r20Setup(db,id);
 await db.exec(`alter table public.invoice_approval_audit add company_id uuid;
 insert into public.invoice_approvals values('${id(10)}','${id(20)}','${id(2)}',2,'pending',null,null),('${id(10)}','${id(21)}','${id(2)}',2,'pending',null,null);
 insert into private.line_invoice_submissions values('${id(24)}','${id(10)}');`);
 for(const table of writeTables)await db.exec(`grant insert,update,delete on public.${table} to authenticated;
 create policy fixture_ordinary_write on public.${table} for all to authenticated
 using(private.r19_scope(company_id)) with check(private.r19_scope(company_id));`);
 for(const entry of catalog21){await db.exec(entry.definition);
   const signature=signatures21.find(s=>s.startsWith(`public.${entry.proname}(`));
   await db.exec(`revoke all on function ${signature} from public,anon;grant execute on function ${signature} to authenticated,service_role`);
 }
 original21=await metadata21(db);
}

async function r21Verify(db,id){
 await r20Verify(db,id);
 // SELECT guards do not make an INSERT guard: reproduce the separate gap.
 await db.exec('begin');
 try{await actor21(db,id(2),()=>db.query(`insert into public.communication_notes(id,company_id,group_id,body) values($1,$2,$3,'synthetic')`,[id(70),id(10),id(31)]));checks21++;
 await actor21(db,id(2),()=>db.query('select public.approve_invoice($1)',[id(21)]));checks21++;
 }finally{await db.exec('rollback');}
 await db.exec(await fs.readFile(new URL('./r21_candidate.sql.review-only',import.meta.url),'utf8'));
 for(const table of ['communication_notes','communication_albums','communication_album_items']){
   await actor21(db,id(2),()=>assert.rejects(db.query(`insert into public.${table}(id,company_id,group_id,body) values($1,$2,$3,'synthetic')`,[id(70),id(10),id(31)]),e=>e.code==='42501'));checks21++;
   await actor21(db,id(2),()=>assert.rejects(db.query(`update public.${table} set group_id=$1 where id=$2`,[id(31),id(20)]),e=>e.code==='42501'));checks21++;
 }
 await actor21(db,id(2),()=>assert.rejects(db.query('update public.invoices set id=$1 where id=$2',[id(24),id(20)]),e=>e.code==='42501'));checks21++;
 await actor21(db,id(2),()=>assert.rejects(db.query('update public.communication_notes set company_id=$1 where id=$2',[id(11),id(20)]),e=>e.code==='42501'));checks21++;
 await db.exec('begin');try{
   await actor21(db,id(2),()=>db.query('update public.communication_notes set group_id=$1',[id(30)]));
   assert.equal((await db.query('select group_id from public.communication_notes where id=$1',[id(21)])).rows[0].group_id,id(31));checks21++;
   await actor21(db,id(1),()=>db.query("update public.communication_notes set body='master' where id=$1",[id(21)]));
   assert.equal((await db.query('select body from public.communication_notes where id=$1',[id(21)])).rows[0].body,'master');checks21++;
   for(const [actor,group]of [[id(1),id(31)],[id(2),id(30)]]){
     await actor21(db,actor,()=>db.query(`insert into public.communication_notes(id,company_id,group_id,body) values($1,$2,$3,'synthetic')`,[id(actor===id(1)?71:72),id(10),group]));checks21++;
   }
 }finally{await db.exec('rollback');}
 for(const table of writeTables){
   await db.exec('begin');
   try{
     await actor21(db,id(2),()=>db.exec(`update public.${table} set body='synthetic-change'`));
     const rows=(await db.query(`select id,body from public.${table} order by id`)).rows;
     assert.equal(rows.find(r=>[id(21),id(31)].includes(r.id)).body,'linked');checks21++;
     assert.equal(rows.find(r=>r.id===id(20)).body,'synthetic-change');checks21++;
     await actor21(db,id(2),()=>db.exec(`delete from public.${table}`));
     assert.ok((await db.query(`select id from public.${table}`)).rows.some(r=>[id(21),id(31)].includes(r.id)));checks21++;
   }finally{await db.exec('rollback');}
 }
 for(const name of ['approve_invoice','cancel_invoice_approval','set_invoice_stamp_display_date']){
   const args=name==='set_invoice_stamp_display_date'?[id(21),id(2),'2026-10-15']:[id(21)];
   await actor21(db,id(2),()=>assert.rejects(db.query(`select public.${name}(${args.map((_,i)=>'$'+(i+1)).join(',')})`,args),e=>e.code==='42501'));checks21++;
 }
 for(const [actor,invoice]of [[id(1),id(21)],[id(2),id(20)]]){
   await db.exec('begin');try{
     await actor21(db,actor,()=>db.query('select public.approve_invoice($1)',[invoice]));
     assert.equal((await db.query('select status from public.invoice_approvals where invoice_id=$1 and approver_user_id=$2',[invoice,actor])).rows[0].status,'approved');checks21++;
     await actor21(db,actor,()=>db.query('select public.set_invoice_stamp_display_date($1,$2,$3)',[invoice,actor,'2026-10-15']));checks21++;
     await actor21(db,actor,()=>db.query('select public.cancel_invoice_approval($1)',[invoice]));
     assert.equal((await db.query('select status from public.invoice_approvals where invoice_id=$1 and approver_user_id=$2',[invoice,actor])).rows[0].status,'pending');checks21++;
   }finally{await db.exec('rollback');}
 }
 for(const table of ['line_history_analysis_groups','line_invoice_submissions','line_historical_invoice_links','line_attendance_submissions']){
   for(const role of ['anon','authenticated']){
     const p=(await db.query("select has_table_privilege($1,$2,'SELECT,INSERT,UPDATE,DELETE') allowed",[role,'private.'+table])).rows[0];
     assert.equal(p.allowed,false);checks21++;
   }
 }
 const after=await metadata21(db);
 for(let i=0;i<after.length;i++)for(const key of ['oid','owner','acl','config']){assert.equal(after[i][key],original21[i][key]);checks21++;}
}

async function r21Http(db,id,token,origin){
 await r20Http(db,id,token,origin);
 await db.exec("notify pgrst, 'reload schema'");
 for(const name of ['approve_invoice','cancel_invoice_approval','set_invoice_stamp_display_date']){
   const body={p_invoice_id:id(21),...(name==='set_invoice_stamp_display_date'?{p_approver_user_id:id(2),p_display_date:'2026-10-15'}:{})};
   const response=await fetch(new URL('/rpc/'+name,origin),{method:'POST',redirect:'error',headers:{Authorization:'Bearer '+token(id(2)),'Content-Type':'application/json'},body:JSON.stringify(body)});
   assert.equal(response.status,403);checks21++;
 }
 for(const table of ['communication_notes','communication_albums','communication_album_items']){
   const response=await fetch(new URL('/'+table,origin),{method:'POST',redirect:'error',headers:{Authorization:'Bearer '+token(id(2)),'Content-Type':'application/json'},body:JSON.stringify({id:id(70),company_id:id(10),group_id:id(31),body:'synthetic'})});
   assert.equal(response.status,403);checks21++;
 }
 const response=await fetch(new URL('/communication_notes?id=eq.'+id(20),origin),{method:'PATCH',redirect:'error',headers:{Authorization:'Bearer '+token(id(2)),'Content-Type':'application/json'},body:JSON.stringify({body:'http-ordinary'})});
 assert.ok([200,204].includes(response.status));
 assert.equal((await db.query('select body from public.communication_notes where id=$1',[id(20)])).rows[0].body,'http-ordinary');checks21++;
 await db.query("update public.communication_notes set body='ordinary' where id=$1",[id(20)]);
}

async function r21Restore(db){
 for(const entry of catalog21)await db.exec(entry.definition);
 assert.deepEqual(await metadata21(db),original21);checks21++;
 for(const table of writeTables)await db.exec(`drop policy r21_boundary on public.${table}`);
 const last=catalog21.find(r=>r.proname==='set_invoice_stamp_display_date');
 await db.exec(last.definition.replace('AS $function$','AS $function$ -- isolated drift\n'));
 const drifted=await metadata21(db);
 await assert.rejects(db.exec(await fs.readFile(new URL('./r21_candidate.sql.review-only',import.meta.url),'utf8')),e=>e.code==='55000');checks21++;
 await db.exec('rollback');
 assert.deepEqual(await metadata21(db),drifted);checks21++;
 assert.equal((await db.query("select count(*)::int n from pg_policies where policyname='r21_boundary'")).rows[0].n,0);checks21++;
 await db.exec(last.definition);assert.deepEqual(await metadata21(db),original21);checks21++;
 await r20Restore(db);
 console.log(`PASS ${checks21} R21 selected write/approval checks and exact function restoration; creation windows, company-global approvers, invitations and final attendance remain blockers.`);
}

if(fileURLToPath(import.meta.url)===process.argv[1]){
 const source=await fs.readFile(new URL('./r19_fixture.mjs',import.meta.url),'utf8');
 assert.equal(createHash('sha256').update(source).digest('hex'),'4a07279de9ee5e4d72075efa994737f419d28a7fad5f6d12901a1447dc611586');
 const self=await fs.readFile(fileURLToPath(import.meta.url),'utf8');
 const hooks=self.slice(0,self.indexOf("if(fileURLToPath(import.meta.url)===process.argv[1])"));
 let adapted=hooks+'\n'+source.replace(/^import .*;\n/gm,'');
 for(const [anchor,replacement]of [
 ['  const before=await Promise.all','  await r21Setup(db,id);\n  const before=await Promise.all'],
 ['  const helpers=(await db.query','  await r21Verify(db,id);\n  const helpers=(await db.query'],
 ["    console.log('VERIFIED actual PG17","    await r21Http(db,id,token,origin);\n    console.log('VERIFIED actual PG17"],
 ['  for(let i=0;i<tables.length;i++){','  await r21Restore(db);\n  for(let i=0;i<tables.length;i++){']
 ]){assert.equal(adapted.split(anchor).length,2);adapted=adapted.replace(anchor,replacement);}
 const temp=new URL(`./.r21-${randomUUID()}.mjs`,import.meta.url);
 try{await fs.writeFile(temp,adapted,{mode:0o600,flag:'wx'});await import(temp.href);}
 finally{await fs.unlink(temp).catch(()=>{});}
}
