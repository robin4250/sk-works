// Disposable database only. Historical documents must never receive live styles.
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import assert from 'node:assert/strict';
const {PGlite}=await import(pathToFileURL(resolve(process.argv[2])).href);
const db=new PGlite();
try {
 await db.exec(`create role anon;create role authenticated;create schema private;create schema auth;
 create function auth.uid() returns uuid language sql as $$select null::uuid$$;
 create function private.account_access_allowed() returns boolean language sql as $$select true$$;
 create table companies(id uuid primary key,name text,company_seal_enabled boolean default true,updated_at timestamptz);
 create table company_members(company_id uuid,user_id uuid,role text);
 create table invoices(id uuid primary key,company_id uuid,snapshot jsonb);
 create table payment_certificates(id uuid primary key,company_id uuid,snapshot jsonb);
 create table payroll_statements(id uuid primary key,company_id uuid,detail jsonb);
 insert into companies(id,name) values('00000000-0000-0000-0000-000000000001','株式会社テスト建設');
 insert into invoices values('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000001','{"old":true}');
 insert into payment_certificates select id,company_id,snapshot from invoices;
 insert into payroll_statements select id,company_id,snapshot from invoices;
 create function private.refresh_automatic_invoice(cid uuid,partner uuid,day date) returns void language plpgsql as $$
 declare existing public.invoices; snapshot_value jsonb;
 begin snapshot_value:='{}';if existing.id is null then return;end if;end $$;
 create function private.refresh_automatic_payment_certificate(cid uuid,partner uuid,day date) returns void language plpgsql as $$
 declare existing public.payment_certificates; snapshot_value jsonb;
 begin snapshot_value:='{}';if existing.id is null then return;end if;end $$;
 create function private.payroll_document_metadata(p_statement_id uuid) returns jsonb language sql as $$
 select jsonb_build_object('company_seal_enabled',c.company_seal_enabled,'old',true)
 from payroll_statements ps join companies c on c.id=ps.company_id where ps.id=p_statement_id $$;
 create table private.saved_agreements(id uuid primary key,snapshot jsonb);
 create function private.saved_site_payment_document(p_proposal uuid,p_company uuid) returns jsonb language plpgsql as $$
 declare result jsonb;
 begin select snapshot into result from private.saved_agreements where id=p_proposal;
 if result is null then
 select jsonb_build_object('snapshot_version',2,'parent_company_seal_enabled',parent.company_seal_enabled)
 into result from companies parent where parent.id=p_company;
 insert into private.saved_agreements values(p_proposal,result);
 end if;return result;end $$;
 insert into private.saved_agreements values('00000000-0000-0000-0000-000000000002','{"snapshot_version":1}'),
 ('00000000-0000-0000-0000-000000000003','{"snapshot_version":2}');`);
 await db.exec(readFileSync('supabase/migrations/20261009011357_company_seal_aoyagi_style.sql','utf8'));
 await db.exec(readFileSync('supabase/migrations/20261009012730_company_seal_document_snapshots.sql','utf8'));
 if(process.argv.includes('--png')) {
  await db.exec(readFileSync('supabase/migrations/20261010160154_company_seal_png_designs.sql','utf8'));
  const pngCid='0f117273-0a06-4a2f-85ec-720a3c9f4cf4';
  const actor='00000000-0000-0000-0000-000000000099';
  await db.exec(`insert into companies(id,name) values('${pngCid}','すみだ建設株式会社');
   insert into company_members values('${pngCid}','${actor}','admin');
   create or replace function auth.uid() returns uuid language sql as $$select '${actor}'::uuid$$;`);
  const styles=['png_sumida_v1_standard','png_sumida_v1_light','png_sumida_v1_worn'];
  const settings=(await db.query('select public.company_seal_style_settings($1) value',[pngCid])).rows[0].value;
  assert.deepEqual(settings.png_styles,styles);
  for(const style of styles) {
   const saved=(await db.query('select public.save_company_seal_style($1,$2,$3) value',[pngCid,style,'すみだ建設株式会社'])).rows[0].value;
   assert.equal(saved.company_seal_style,style);
   for(const [table,column] of [['invoices','snapshot'],['payment_certificates','snapshot'],['payroll_statements','detail']]) {
    const id=(await db.query(`insert into ${table} values(gen_random_uuid(),$1,'{}') returning id`,[pngCid])).rows[0].id;
    const initial=(await db.query(`select ${column} value from ${table} where id=$1`,[id])).rows[0].value;
    assert.deepEqual(initial.company_seal_snapshot,{version:1,style,name:'すみだ建設株式会社',company_id:pngCid});
    await db.query("select public.save_company_seal_style($1,'legacy',$2)",[pngCid,'すみだ建設株式会社']);
    await db.query(`update ${table} set ${column}='{}' where id=$1`,[id]);
    assert.deepEqual((await db.query(`select ${column} value from ${table} where id=$1`,[id])).rows[0].value,initial);
    await db.query('select public.save_company_seal_style($1,$2,$3)',[pngCid,style,'すみだ建設株式会社']);
   }
  }
  await assert.rejects(db.query("select public.save_company_seal_style($1,$2,'旧社名')",[pngCid,styles[0]]),e=>e.code==='40001');
  await assert.rejects(db.query("update companies set company_seal_style=$1 where id<>$2",[styles[0],pngCid]),e=>e.code==='23514');
  await db.exec(`update company_members set role='viewer' where company_id='${pngCid}'`);
  await assert.rejects(db.query('select public.save_company_seal_style($1,$2,$3)',[pngCid,styles[0],'すみだ建設株式会社']),e=>e.code==='42501');
  await db.exec(`delete from company_members where company_id='${pngCid}'`);
  await assert.rejects(db.query('select public.company_seal_style_settings($1)',[pngCid]),e=>e.code==='42501');
  await db.exec(`create or replace function auth.uid() returns uuid language sql as $$select null::uuid$$;`);
  await assert.rejects(db.query('select public.save_company_seal_style($1,$2,$3)',[pngCid,styles[0],'すみだ建設株式会社']),e=>e.code==='42501');
  // Remove only this disposable fixture, so original historical tests stay intact.
  for(const t of ['invoices','payment_certificates','payroll_statements']) await db.query(`delete from ${t} where company_id=$1`,[pngCid]);
  await db.query('delete from companies where id=$1',[pngCid]);
  console.log('PASS: three PNG styles, exact company, role/name guards, all three immutable document snapshots');
 }
 const cid='00000000-0000-0000-0000-000000000001';
 await db.exec(`update companies set company_seal_style='aoyagi_reisho'`);
 for(const [table,column] of [['invoices','snapshot'],['payment_certificates','snapshot'],['payroll_statements','detail']]) {
  // Old manual/finalized/draft JSON all retain absence: a spoofed new key is stripped.
  await db.exec(`update ${table} set ${column}=${column}||'{"company_seal_snapshot":{"style":"aoyagi_reisho"}}'`);
  assert.deepEqual((await db.query(`select ${column} value from ${table}`)).rows[0].value,{old:true});
  await db.exec(`insert into ${table} values('00000000-0000-0000-0000-000000000004','${cid}','{}')`);
  const stored=(await db.query(`select ${column}->'company_seal_snapshot' value from ${table} where id='00000000-0000-0000-0000-000000000004'`)).rows[0].value;
  assert.deepEqual(stored,{version:1,style:'aoyagi_reisho',name:'株式会社テスト建設'});
  await db.exec(`update companies set name='株式会社改名',company_seal_style='legacy';update ${table} set ${column}='{}' where id='00000000-0000-0000-0000-000000000004'`);
  assert.deepEqual((await db.query(`select ${column}->'company_seal_snapshot' value from ${table} where id='00000000-0000-0000-0000-000000000004'`)).rows[0].value,stored);
  await db.exec(`update companies set name='株式会社テスト建設',company_seal_style='aoyagi_reisho'`);
 }
 for(const [id,version] of [['00000000-0000-0000-0000-000000000002',1],['00000000-0000-0000-0000-000000000003',2]]) {
  assert.deepEqual((await db.query('select private.saved_site_payment_document($1,$2) value',[id,cid])).rows[0].value,{snapshot_version:version});
 }
 const agreement=(await db.query('select private.saved_site_payment_document($1,$2) value',['00000000-0000-0000-0000-000000000004',cid])).rows[0].value;
 assert.equal(agreement.snapshot_version,3);assert.equal(agreement.company_seal_snapshot.style,'aoyagi_reisho');
 await db.exec(`update companies set name='株式会社𠮷野'`);
 await assert.rejects(db.query("insert into invoices values(gen_random_uuid(),$1,'{}')",[cid]),e=>e.code==='22023');
 // Even a privileged direct company update cannot make a new invalid document.
 await db.exec(`update companies set name='合同会社長い会社名建設工業サービスSKO'`);
 await assert.rejects(db.query("insert into payroll_statements values(gen_random_uuid(),$1,'{}')",[cid]),e=>e.code==='22023');
 const before=(await db.query('select snapshot from invoices where id=$1',['00000000-0000-0000-0000-000000000004'])).rows[0].snapshot;
 assert.deepEqual((await db.query('select private.document_company_seal_snapshot($1,$2,false) value',[before,cid])).rows[0].value,{company_seal_snapshot:before.company_seal_snapshot});
 await db.exec('set role authenticated');
 await assert.rejects(db.query("select private.document_company_seal_snapshot('{}',$1,true)",[cid]),e=>e.code==='42501');
 console.log('PASS: new only, old absence preserved, immutable names/styles, v1/v2 agreements unchanged, direct invalid name rejected, helper ACL');
} finally {await db.close();}
