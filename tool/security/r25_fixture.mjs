import assert from 'node:assert/strict';import fs from 'node:fs/promises';import {fileURLToPath,pathToFileURL} from 'node:url';import {createHash,createHmac,randomUUID} from 'node:crypto';import {r20Setup,r20Verify,r20Http,r20Restore} from './r20_fixture.mjs';
let checks25=0;let original25;const createNames25=['private.create_line_invoices(uuid,uuid,integer,text)','private.create_line_historical_invoices(uuid,uuid,text,jsonb,integer,boolean,text,boolean)'];const signatures25=['private.r19_invoice_allowed(uuid)','private.r20_linked_notice(text,uuid)','private.ensure_invoice_approval_rows(uuid)',...createNames25];
const metadata25=async db=>(await db.query(`select p.oid::text,pg_get_functiondef(p.oid) definition,pg_get_userbyid(p.proowner) owner,p.proacl::text acl,p.proconfig::text config,p.prosecdef from pg_proc p where p.oid=any($1::regprocedure[]) order by p.oid`,[signatures25])).rows;
async function r25Setup(db,id){
 await db.exec(`alter table private.line_invoice_submissions rename to r25_old_lineage;
 create table private.line_invoice_submissions(company_id uuid,customer_id uuid,work_month date,draft_id uuid,draft_revision integer,invoice_id uuid);
 insert into private.line_invoice_submissions(company_id,invoice_id) select company_id,invoice_id from private.r25_old_lineage;
 alter table private.line_historical_invoice_links add customer_id uuid,add work_month date,add quote_id uuid,add actor_id uuid,add command_id uuid,add invoice_fingerprint text;
 create table private.line_import_drafts(id uuid primary key,company_id uuid,group_id uuid,work_month date,revision integer,source_kind text,source_messages jsonb);
 create table private.line_import_commands(company_id uuid,actor_id uuid,command_id uuid,payload jsonb,result jsonb,unique(company_id,actor_id,command_id));
 create table private.line_historical_quote_snapshots(id uuid primary key,company_id uuid,group_id uuid,work_month date,draft_id uuid,draft_revision integer,source_fingerprint text,snapshot jsonb,input_rates jsonb);
 create table private.line_historical_invoice_commands(company_id uuid,actor_id uuid,command_id uuid,quote_id uuid,group_id uuid,work_month date,payload jsonb,result jsonb,unique(company_id,actor_id,command_id));
 insert into private.line_import_drafts values('${id(70)}','${id(10)}','${id(31)}','2026-08-01',1,'fixture','[]');
 insert into private.line_historical_quote_snapshots values('${id(71)}','${id(10)}','${id(31)}','2026-08-01','${id(70)}',1,'source','{"rows":[],"source_messages":[]}','{}');
 create function private.line_import_access(uuid,text) returns void language plpgsql as $$begin if not private.r19_master() then raise exception 'fixture master required' using errcode='42501';end if;end$$;
 create function private.require_current_line_import_draft(p_id uuid,p_rev integer,p_kind text) returns private.line_import_drafts language plpgsql as $$declare d private.line_import_drafts;begin perform private.line_import_access(null,p_kind);select * into d from private.line_import_drafts where id=p_id and revision=p_rev;if not found then raise exception 'fixture draft mismatch';end if;return d;end$$;
 create function private.require_line_historical_invoice_quote(p_id uuid) returns private.line_historical_quote_snapshots language plpgsql as $$declare q private.line_historical_quote_snapshots;begin perform private.line_import_access(null,'invoice');select * into q from private.line_historical_quote_snapshots where id=p_id;if not found then raise exception 'fixture quote mismatch';end if;return q;end$$;
 create function private.line_invoice_preview(uuid,integer) returns jsonb language sql as $$select jsonb_build_object('fingerprint','fixture','quotes',jsonb_build_array(jsonb_build_object('customer_id','${id(99)}','customer_name','fixture','customer_address','fixture','tax_rate_bps',1000,'subtotal',10000,'tax',1000,'welfare',0,'grand_total',11000,'sites',jsonb_build_array())))$$;
 create function private.line_historical_invoice_preview(uuid,text,jsonb,integer,boolean) returns jsonb language sql as $$select private.line_invoice_preview(null,1)$$;
 create table private.r25_observations(invoice_id uuid,pending boolean,hidden boolean,linked_notice boolean);
 `);
 for(const row of catalog24.creationOrder){await db.exec(row.definition);const sig=createNames25.find(x=>x.startsWith('private.'+row.proname+'('));await db.exec(`revoke all on function ${sig} from public,anon,service_role;grant execute on function ${sig} to authenticated`);}
 await db.exec(trigger24.definition);await db.exec(catalog24.trigger);
 original25=await metadata25(db);
}
async function call25(db,id,kind,command){return actor23(db,id(1),()=>kind==='current'?db.query('select private.create_line_invoices($1,$2,1,$3) result',[command,id(70),'fixture']):db.query('select private.create_line_historical_invoices($1,$2,$3,$4,1000,true,$3,true) result',[command,id(71),'fixture',JSON.stringify([{customer_id:id(99)}])]));}
const iid25=r=>r.rows[0].result.invoices[0].invoice_id;
async function verifyResult25(db,iid){
 assert.equal((await db.query('select count(*)::int n from private.r25_registry')).rows[0].n,0);checks25++;
 assert.equal((await db.query('select count(*)::int n from public.invoice_approvals where invoice_id=$1',[iid])).rows[0].n,0);checks25++;
 assert.equal((await db.query('select count(*)::int n from public.app_notifications where action_id=$1',[iid])).rows[0].n,0);checks25++;
 assert.equal(Number((await db.query('select grand_total from public.invoices where id=$1',[iid])).rows[0].grand_total),11000);checks25++;
}
async function r25Verify(db,id){
 await r25Setup(db,id);const before=await snapshot23(db);
 // Original exact creation and actual trigger expose the ordering gap.
 await db.exec('begin');try{await db.query('update public.invoice_approvers set user_id=$1',[id(2)]);const iid=iid25(await call25(db,id,'current',id(91)));assert.equal((await db.query('select count(*)::int n from public.invoice_approvals where invoice_id=$1',[iid])).rows[0].n,1);assert.equal((await db.query('select count(*)::int n from public.app_notifications where action_id=$1',[iid])).rows[0].n,1);checks25+=2;}finally{await db.exec('rollback');}
 await db.exec(await fs.readFile(new URL('./r25_candidate.sql.review-only',import.meta.url),'utf8'));
 await db.exec(`create function private.r25_observe() returns trigger language plpgsql security definer set search_path='' as $$declare old_claims text;invisible boolean;begin old_claims:=current_setting('request.jwt.claims',true);perform set_config('request.jwt.claims','{"sub":"${id(2)}"}',true);invisible:=not private.r19_invoice_allowed(new.id);perform set_config('request.jwt.claims',old_claims,true);insert into private.r25_observations values(new.id,exists(select 1 from private.r25_registry p where p.invoice_id=new.id and p.company_id=new.company_id and p.actor_id=auth.uid()),invisible,private.r20_linked_notice('invoice_approval',new.id));return null;end$$;create trigger a_r25_observer after insert on public.invoices for each row execute function private.r25_observe();`);
 for(const kind of ['current','historical']){
 await db.exec('begin');try{
 await db.query('update public.invoice_approvers set user_id=$1',[id(2)]);const first=await call25(db,id,kind,id(92));const iid=iid25(first);await verifyResult25(db,iid);
 assert.deepEqual((await db.query('select pending,hidden,linked_notice from private.r25_observations where invoice_id=$1',[iid])).rows,[{pending:true,hidden:true,linked_notice:true}]);checks25++;
 assert.deepEqual(await call25(db,id,kind,id(92)),first);checks25++;
 assert.equal((await db.query('select count(*)::int n from public.invoices where id=$1',[iid])).rows[0].n,1);checks25++;
 }finally{await db.exec('rollback');}
 assert.deepEqual(await snapshot23(db),before);checks25++;
 }
 for(const role of ['anon','authenticated','service_role'])for(const privilege of ['SELECT','INSERT','UPDATE','DELETE']){assert.equal((await db.query('select has_table_privilege($1,$2,$3) p',[role,'private.r25_registry',privilege])).rows[0].p,false);checks25++;}
 for(const statement of ['select * from private.r25_registry',`insert into private.r25_registry values('${id(90)}','${id(10)}','${id(2)}')`,'update private.r25_registry set actor_id=null','delete from private.r25_registry']){await actor23(db,id(2),()=>assert.rejects(db.exec(statement),e=>e.code==='42501'));checks25++;}
 await db.exec(`create function private.r25_fail() returns trigger language plpgsql as $$begin raise exception 'fixture injected failure';end$$;create trigger z_r25_failure after insert on public.invoices for each row execute function private.r25_fail();`);
 await assert.rejects(call25(db,id,'current',id(93)),/fixture injected failure/);assert.equal((await db.query('select count(*)::int n from private.r25_registry')).rows[0].n,0);assert.deepEqual(await snapshot23(db),before);checks25+=3;await db.exec('drop trigger z_r25_failure on public.invoices');
 // A NULL server authorization result must never be treated as permission.
 await db.exec('begin');try{await db.exec("create or replace function private.r19_master() returns boolean language sql stable security definer set search_path='' as $$select null::boolean$$");await assert.rejects(call25(db,id,'current',id(96)),e=>e.code==='42501');checks25++;}finally{await db.exec('rollback');}assert.equal((await db.query('select count(*)::int n from private.r25_registry')).rows[0].n,0);assert.deepEqual(await snapshot23(db),before);checks25+=2;
 // A fresh command succeeds after a failed transaction; prior partial state is absent.
 await db.exec('begin');try{const iid=iid25(await call25(db,id,'current',id(94)));await verifyResult25(db,iid);}finally{await db.exec('rollback');}checks25++;
 // Force a UUID collision only in this disposable function body; existing PK refuses atomically.
 const patched25=(await metadata25(db)).find(r=>r.definition.includes('FUNCTION private.create_line_invoices('));
 await db.exec(patched25.definition.replace('iid:=gen_random_uuid();',"iid:='"+id(20)+"'::uuid;"));
 try{await assert.rejects(call25(db,id,'current',id(95)),e=>e.code==='23505');assert.equal((await db.query('select count(*)::int n from private.r25_registry')).rows[0].n,0);assert.deepEqual(await snapshot23(db),before);checks25+=3;}finally{await db.exec(patched25.definition);}
 const after=await metadata25(db);for(let i=0;i<after.length;i++)for(const key of ['oid','owner','acl','config','prosecdef']){assert.equal(after[i][key],original25[i][key]);checks25++;}
}
async function r25Http(db,id,token,origin){
 for(const row of catalog24.creationOrder){const kind=row.proname==='create_line_invoices'?'current':'historical';await db.exec(kind==='current'?`create function public.r25_current(p_command uuid) returns jsonb language sql security invoker set search_path='' as $$select private.create_line_invoices(p_command,'${id(70)}',1,'fixture')$$`:`create function public.r25_historical(p_command uuid) returns jsonb language sql security invoker set search_path='' as $$select private.create_line_historical_invoices(p_command,'${id(71)}','fixture','[{"customer_id":"${id(99)}"}]',1000,true,'fixture',true)$$`);await db.exec(`revoke all on function public.r25_${kind}(uuid) from public,anon;grant execute on function public.r25_${kind}(uuid) to authenticated`);}
 await db.exec("notify pgrst,'reload schema'");let ready25=false;for(let attempt=0;attempt<30;attempt++){const probe=await fetch(new URL('/rpc/r25_current',origin),{method:'POST',headers:{Authorization:'Bearer '+token(id(2)),'Content-Type':'application/json'},body:JSON.stringify({p_command:randomUUID()}),redirect:'error'});if(probe.status===403){ready25=true;break;}assert.ok([404,503].includes(probe.status),'Unexpected creation probe status '+probe.status);await new Promise(resolve=>setTimeout(resolve,100));}assert.ok(ready25,'Disposable creation schema cache not ready');const before=await snapshot23(db);
 for(const kind of ['current','historical']){
 const command=randomUUID();let iid;
 try{
 await db.query('update public.invoice_approvers set user_id=$1',[id(2)]);
 const invoke=actor=>fetch(new URL('/rpc/r25_'+kind,origin),{method:'POST',redirect:'error',headers:{Authorization:'Bearer '+token(actor),'Content-Type':'application/json'},body:JSON.stringify({p_command:command})});
 const denied=await invoke(id(2));assert.equal(denied.status,403);checks25++;
 const response=await invoke(id(1));assert.equal(response.status,200);const result=await response.json();iid=result.invoices[0].invoice_id;await verifyResult25(db,iid);
 const again=await invoke(id(1));assert.equal(again.status,200);assert.deepEqual(await again.json(),result);checks25++;
 const ordinary=await fetch(new URL('/invoices?id=eq.'+iid,origin),{headers:{Authorization:'Bearer '+token(id(2))},redirect:'error'});assert.equal(ordinary.status,200);assert.deepEqual(await ordinary.json(),[]);checks25++;
 }finally{
 if(iid){await db.query('delete from private.line_invoice_submissions where invoice_id=$1',[iid]);await db.query('delete from private.line_historical_invoice_links where invoice_id=$1',[iid]);await db.query('delete from public.app_notifications where action_id=$1',[iid]);await db.query('delete from public.invoice_approvals where invoice_id=$1',[iid]);await db.query('delete from public.invoices where id=$1',[iid]);await db.query('delete from private.r25_observations where invoice_id=$1',[iid]);}
 await db.query('delete from private.line_import_commands where command_id=$1',[command]);await db.query('delete from private.line_historical_invoice_commands where command_id=$1',[command]);await db.exec('delete from public.invoice_approvers');await db.query('insert into public.invoice_approvers select * from jsonb_populate_recordset(null::public.invoice_approvers,$1::jsonb)',[JSON.stringify(before.invoice_approvers)]);
 }
 assert.deepEqual(await snapshot23(db),before);checks25++;
 }
}
async function r25Restore(db){for(const row of original25)await db.exec(row.definition);assert.deepEqual(await metadata25(db),original25);checks25++;assert.equal((await db.query('select count(*)::int n from private.r25_registry')).rows[0].n,0);checks25++;await db.exec('drop table private.r25_registry');const last25=original25.find(r=>r.definition.includes('FUNCTION private.create_line_historical_invoices('));await db.exec(last25.definition.replace('AS $function$','AS $function$ -- fixture drift\n'));const drifted25=await metadata25(db);await assert.rejects(db.exec(await fs.readFile(new URL('./r25_candidate.sql.review-only',import.meta.url),'utf8')),e=>e.code==='55000');checks25++;await db.exec('rollback');assert.deepEqual(await metadata25(db),drifted25);checks25++;assert.equal((await db.query("select to_regclass('private.r25_registry') r")).rows[0].r,null);checks25++;await db.exec(last25.definition);assert.deepEqual(await metadata25(db),original25);checks25++;console.log(`PASS ${checks25} R25 actual creation and trigger boundary checks; fixture quote/access helpers are not production auth proof.`);}
const source25=await fs.readFile(new URL('./r24_fixture.mjs',import.meta.url),'utf8');const source23=await fs.readFile(new URL('./r23_fixture.mjs',import.meta.url),'utf8');const source22=await fs.readFile(new URL('./r22_fixture.mjs',import.meta.url),'utf8');const source21=await fs.readFile(new URL('./r21_fixture.mjs',import.meta.url),'utf8');const source19=await fs.readFile(new URL('./r19_fixture.mjs',import.meta.url),'utf8');const self25=await fs.readFile(fileURLToPath(import.meta.url),'utf8');
let adapted25=self25.slice(0,self25.indexOf('const source25='))+'\n'+source25.slice(0,source25.indexOf('const source24=')).replace(/^import .*;\n/gm,'')+'\n'+source23.slice(0,source23.indexOf('const source23=')).replace(/^import .*;\n/gm,'')+'\n'+source22.slice(0,source22.indexOf('const source22=')).replace(/^import .*;\n/gm,'')+'\n'+source21.slice(0,source21.indexOf("if(fileURLToPath(import.meta.url)===process.argv[1])")).replace(/^import .*;\n/gm,'')+'\n'+source19.replace(/^import .*;\n/gm,'');
for(const [anchor,replacement]of [
 ['  const before=await Promise.all','  await r21Setup(db,id);await r22Setup(db,id);await r23Setup(db,id);await r24Setup(db);await db.exec("alter table public.invoices alter id set default gen_random_uuid(),add subtotal numeric,add welfare_amount numeric,add adjustments numeric,add detail_mode text,add automatic_calculation boolean");\n  const before=await Promise.all'],
 ['  const helpers=(await db.query','  await r21Verify(db,id);await r22Verify(db,id);await r23Verify(db,id);await r24Verify(db,id);await r25Verify(db,id);\n  const helpers=(await db.query'],
 ["    console.log('VERIFIED actual PG17","    await r21Http(db,id,token,origin);await r22Http(db,id,token,origin);await r23Http(db,id,token,origin);await r24Http(db,id,token,origin);await r25Http(db,id,token,origin);\n    console.log('VERIFIED actual PG17"],
 ['  for(let i=0;i<tables.length;i++){','  await r25Restore(db);await r24Restore(db);await r23Restore(db);await r22Restore(db);await r21Restore(db);\n  for(let i=0;i<tables.length;i++){']
 ]){assert.equal(adapted25.split(anchor).length,2);adapted25=adapted25.replace(anchor,replacement);}
const temp25=new URL(`./.r25-${randomUUID()}.mjs`,import.meta.url);try{await fs.writeFile(temp25,adapted25,{mode:0o600,flag:'wx'});await import(temp25.href);}finally{await fs.unlink(temp25).catch(()=>{});}
