import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createHash, createHmac, randomUUID } from 'node:crypto';

const catalog=JSON.parse(await fs.readFile(new URL('./r20_catalog.json',import.meta.url),'utf8'));
const signatures=catalog.map(r=>`${r.nspname}.${r.proname}(${r.args.split(', ').map(a=>a.split(' ').at(-1)).join(',')})`);
let original;
let checks=0;
const metadata=async db=>(await db.query(`select p.oid::text,pg_get_functiondef(p.oid) definition,
 pg_get_userbyid(p.proowner) owner,p.proacl::text acl,p.proconfig::text config
 from pg_proc p where p.oid=any($1::regprocedure[]) order by p.oid`,[signatures])).rows;
const asActor=async(db,actor,fn)=>{await db.exec('set role authenticated');try{
 await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:actor})]);return await fn();
}finally{await db.exec('reset role').catch(()=>{});}};

export async function r20Setup(db,id){
 await db.exec(`create role service_role;
 create table public.companies(id uuid,name text,address text,corporate_number text,company_seal_enabled boolean,invoice_stamp_date_mode text);
 create table public.company_members(company_id uuid,user_id uuid,role text);
 insert into public.companies values('${id(10)}','Synthetic Company','fixture','0000000000000',false,'closing');
 insert into public.company_members select company_id,user_id,'admin' from private.r19_members;
 create table public.customers(id uuid,company_id uuid,name text,billing_name text,billing_address text);
 insert into public.customers values('${id(99)}','${id(10)}','Synthetic Customer','','fixture');
 create table public.partner_companies(id uuid,company_id uuid,name text,address text,president_name text);
 create table public.payment_certificates(id uuid,company_id uuid,partner_company_id uuid,period_start date,period_end date,revision int,status text,finalized_at timestamptz,gross_amount bigint,snapshot jsonb,calculation_blocked boolean);
 alter table public.invoices add customer_id uuid default '${id(99)}',add billing_period_start date default '2026-10-01',add billing_period_end date default '2026-10-31',add updated_at timestamptz default '2026-10-01T00:00:00Z',add status text default 'draft',add finalized_at timestamptz,add grand_total bigint default 110000,add tax bigint default 10000,add snapshot jsonb default '{}',add calculation_blocked boolean default false,add approval_finalized_at timestamptz,add invoice_seal_frozen boolean default false;
 create table public.invoice_approvals(company_id uuid,invoice_id uuid,approver_user_id uuid,position int,status text,approved_at timestamptz,display_date_override date);
 insert into public.invoice_approvals values('${id(10)}','${id(20)}','${id(1)}',1,'pending',null,null),('${id(10)}','${id(21)}','${id(1)}',1,'pending',null,null);
 create table public.user_profiles(user_id uuid,display_name text);
 create table public.invoice_approval_audit(id uuid,invoice_id uuid,actor_user_id uuid,action text,created_at timestamptz);
 insert into public.invoice_approval_audit values('${id(90)}','${id(20)}','${id(1)}','ordinary','2026-10-01'),('${id(91)}','${id(21)}','${id(1)}','linked','2026-10-01');
 create function private.ensure_invoice_approval_rows(uuid) returns void language sql as $$select$$;
 create function private.has_company_feature(uuid,text) returns boolean language sql as $$select private.r19_scope($1)$$;
 create function private.document_company_seal_snapshot(jsonb,uuid,boolean) returns jsonb language sql as $$select '{"company_seal_snapshot":{"version":1,"style":"legacy"}}'::jsonb$$;
 alter table public.app_notifications alter id set default gen_random_uuid(),add kind text,add title text,add recipient_user_id uuid;
 `);
 for(const entry of catalog){await db.exec(entry.definition);
   await db.exec(`revoke all on function ${signatures[catalog.indexOf(entry)]} from public,anon,authenticated,service_role`);
   if(entry.nspname==='public')await db.exec(`grant execute on function ${signatures[catalog.indexOf(entry)]} to authenticated,service_role`);
 }
 await db.exec(`create function public.r20_trade_probe(p_id uuid) returns jsonb language sql security definer set search_path='' as $$select private.trade_document_source('invoice',p_id,'2026-10-01T00:00:00Z')$$;
 create function public.r20_notice_probe(p_id uuid,p_recipient uuid) returns uuid language sql security definer set search_path='' as $$select private.enqueue_notification('${id(10)}',p_recipient,'approval','synthetic',null,'invoice_approval',p_id)$$;
 revoke all on function public.r20_trade_probe(uuid),public.r20_notice_probe(uuid,uuid) from public,anon;
 grant execute on function public.r20_trade_probe(uuid),public.r20_notice_probe(uuid,uuid) to authenticated;`);
 original=await metadata(db);
 for(const row of original){const expected=catalog.find(x=>row.definition.includes(`FUNCTION ${x.nspname}.${x.proname}(`));
   assert.ok(expected);assert.equal(row.owner,expected.owner);assert.equal(row.acl,expected.acl);checks++;
 }
}

export async function r20Verify(db,id){
 // Prove existing definers bypass the R19 row filter before adding this guard.
 for(const name of ['invoice_approval_history','invoice_approval_status_rows','invoice_approval_status_rows_v2','r20_trade_probe']){
   await asActor(db,id(2),()=>db.query(`select * from public.${name}($1)`,[id(21)]));checks++;
 }
 await db.exec(await fs.readFile(new URL('./r20_candidate.sql.review-only',import.meta.url),'utf8'));
 for(const name of ['invoice_approval_history','invoice_approval_status_rows','invoice_approval_status_rows_v2','r20_trade_probe']){
   for(const actor of [id(2),id(4)]){await asActor(db,actor,()=>assert.rejects(db.query(`select * from public.${name}($1)`,[id(21)]),e=>e.code==='42501'));checks++;}
   assert.ok((await asActor(db,id(1),()=>db.query(`select * from public.${name}($1)`,[id(21)]))).rows.length);checks++;
   assert.ok((await asActor(db,id(2),()=>db.query(`select * from public.${name}($1)`,[id(20)]))).rows.length);checks++;
 }
 const before=(await db.query('select count(*)::int n from public.app_notifications')).rows[0].n;
 const denied=await asActor(db,id(1),()=>db.query('select public.r20_notice_probe($1,$2) id',[id(21),id(2)]));
 assert.equal(denied.rows[0].id,null);assert.equal((await db.query('select count(*)::int n from public.app_notifications')).rows[0].n,before);checks++;
 // Roll back positive enqueue probes to keep the R19 byte snapshots unchanged.
 await db.exec('begin');
 try{assert.ok((await asActor(db,id(1),()=>db.query('select public.r20_notice_probe($1,$2) id',[id(21),id(1)]))).rows[0].id);checks++;
 assert.ok((await asActor(db,id(1),()=>db.query('select public.r20_notice_probe($1,$2) id',[id(20),id(2)]))).rows[0].id);checks++;
 }finally{await db.exec('rollback');}
 const guarded=await metadata(db);
 for(let i=0;i<guarded.length;i++){assert.equal(guarded[i].oid,original[i].oid);
   for(const k of ['owner','acl','config'])assert.equal(guarded[i][k],original[i][k]);checks++;}
}

export async function r20Http(db,id,token,origin){
 await db.exec("notify pgrst, 'reload schema'");
 for(const name of ['invoice_approval_history','invoice_approval_status_rows','invoice_approval_status_rows_v2','r20_trade_probe']){
   for(const actor of [id(1),id(2),id(4)]){
     const response=await fetch(new URL('/rpc/'+name,origin),{method:'POST',redirect:'error',
       headers:{Authorization:'Bearer '+token(actor),'Content-Type':'application/json'},
       body:JSON.stringify(name==='r20_trade_probe'?{p_id:id(21)}:{p_invoice_id:id(21)})});
     assert.equal(response.status,actor===id(1)?200:403);checks++;
   }
 }
 const countBefore=(await db.query('select count(*)::int n from public.app_notifications')).rows[0].n;
 const response=await fetch(new URL('/rpc/r20_notice_probe',origin),{method:'POST',redirect:'error',
   headers:{Authorization:'Bearer '+token(id(1)),'Content-Type':'application/json'},
   body:JSON.stringify({p_id:id(21),p_recipient:id(2)})});
 assert.equal(response.status,200);assert.equal(await response.json(),null);
 assert.equal((await db.query('select count(*)::int n from public.app_notifications')).rows[0].n,countBefore);checks++;
}

export async function r20Restore(db){
 for(const entry of catalog)await db.exec(entry.definition);
 assert.deepEqual(await metadata(db),original);checks++;
 await db.exec('drop function private.r20_linked_notice(text,uuid)');
 const last=catalog.find(r=>r.proname==='enqueue_notification');
 await db.exec(last.definition.replace('AS $function$','AS $function$ -- isolated drift\n'));
 const drifted=await metadata(db);
 await assert.rejects(db.exec(await fs.readFile(new URL('./r20_candidate.sql.review-only',import.meta.url),'utf8')),
   error=>error.code==='55000');checks++;
 await db.exec('rollback');
 assert.deepEqual(await metadata(db),drifted);checks++;
 assert.equal((await db.query("select to_regprocedure('private.r20_linked_notice(text,uuid)')::text f")).rows[0].f,null);checks++;
 await db.exec(last.definition);
 assert.deepEqual(await metadata(db),original);checks++;
 console.log(`PASS ${checks} R20 read/recipient guards and exact original definition/OID/owner/ACL/config restore; public probes are fixture-only, not complete app RPC/push/write closure.`);
}

if(fileURLToPath(import.meta.url)===process.argv[1]){
 const source=await fs.readFile(new URL('./r19_fixture.mjs',import.meta.url),'utf8');
 assert.equal(createHash('sha256').update(source).digest('hex'),
   '4a07279de9ee5e4d72075efa994737f419d28a7fad5f6d12901a1447dc611586');
 // Exact dependency anchors prevent weakening or silently replacing R19 checks.
 const self=await fs.readFile(import.meta.url.startsWith('file:')?fileURLToPath(import.meta.url):import.meta.url,'utf8');
 const hooks=self.slice(0,self.indexOf("if(fileURLToPath(import.meta.url)===process.argv[1])"));
 let adapted=hooks+'\n'+source.replace(/^import .*;\n/gm,'');
 const insertions=[
  ['  const before=await Promise.all','  await r20Setup(db,id);\n  const before=await Promise.all'],
  ['  const helpers=(await db.query','  await r20Verify(db,id);\n  const helpers=(await db.query'],
  ["    console.log('VERIFIED actual PG17", "    await r20Http(db,id,token,origin);\n    console.log('VERIFIED actual PG17"],
  ['  for(let i=0;i<tables.length;i++){','  await r20Restore(db);\n  for(let i=0;i<tables.length;i++){'],
 ];
 for(const [anchor,replacement]of insertions){assert.equal(adapted.split(anchor).length,2);adapted=adapted.replace(anchor,replacement);}
 const temp=new URL(`./.r20-${randomUUID()}.mjs`,import.meta.url);
 try{await fs.writeFile(temp,adapted,{mode:0o600,flag:'wx'});await import(temp.href);}
 finally{await fs.unlink(temp).catch(()=>{});}
}
