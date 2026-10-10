import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
const {PGlite}=await import(process.argv[2]);
const db=new PGlite();
await db.exec(`create role anon; create role authenticated; create schema private; create schema auth;
create function auth.uid() returns uuid language sql as $$ select nullif(current_setting('test.uid',true),'')::uuid $$;
create function private.account_access_allowed() returns boolean language sql as $$ select auth.uid() is not null $$;
create table companies(id uuid primary key,name text,postal_code text,address text,phone text,fax text,company_seal_enabled boolean not null default true); create table company_members(company_id uuid,user_id uuid,role text);
create table sites(id uuid primary key,company_id uuid,name text); create table private.company_connections(parent_company_id uuid,child_company_id uuid,status text);
create table private.document_deliveries(id uuid primary key,sender_company_id uuid,recipient_company_id uuid);
create table private.company_data_delivery_items(id uuid primary key,delivery_id uuid,payload_kind text,payload jsonb);
create table public.site_financial_settings(site_id uuid primary key,billing_square_meter_unit_price_yen integer,billing_square_meter_quantity numeric,billing_contract_amount_yen integer,billing_allowance_1_name text,billing_allowance_1_amount_yen integer,billing_allowance_2_name text,billing_allowance_2_amount_yen integer,billing_allowance_3_name text,billing_allowance_3_amount_yen integer);
create table private.site_share_inbox(data_item_id uuid primary key,recipient_company_id uuid,status text,accepted_site_id uuid);
grant usage on schema private,auth to authenticated;
`);
await db.exec(await fs.readFile(new URL('../supabase/migrations/20261008201215_site_payment_agreement_staged.sql',import.meta.url),'utf8'));
await db.exec(await fs.readFile(new URL('../supabase/migrations/20261008212855_site_payment_company_snapshot.sql',import.meta.url),'utf8'));
const ids=Array.from({length:9},(_,i)=>`00000000-0000-0000-0000-${String(i+1).padStart(12,'0')}`);
const[parent,child,admin1,admin2,site1,site2,delivery,item,outsider]=ids;
await db.exec(`insert into companies(id,name) values('${parent}','親会社'),('${child}','下請会社'); insert into company_members values('${parent}','${admin1}','admin'),('${child}','${admin2}','admin'); insert into sites values('${site1}','${parent}','現場'),('${site2}','${child}','現場'); insert into private.company_connections values('${parent}','${child}','accepted'); insert into private.document_deliveries values('${delivery}','${parent}','${child}'); insert into private.company_data_delivery_items values('${item}','${delivery}','site_share','{"source_site_id":"${site1}"}'); insert into private.site_share_inbox values('${item}','${child}','accepted','${site2}'); set test.uid='${admin1}'; set role authenticated;`);
await assert.rejects(db.query(`select public.site_payment_agreement_workspace('${item}','${parent}')`),/未有効/);
await db.exec(`reset role; insert into private.site_payment_agreement_rollout values('${parent}',true),('${child}',true); set role authenticated;`);
const terms={period_start:'2026-10-01',period_end:'2026-10-31',mode:'square_meter',unit_price_yen:1200,area:12.5,base_amount_yen:15000,adjustments:[],tax_included:false,tax_amount_yen:1500,tax_rate:10,taxable_amount_yen:15000,rounding_rule:'floor',final_amount_yen:16500};
const propose=async(revision,t=terms)=>(await db.query(`select public.propose_site_payment_terms('${item}','${parent}',$1,$2::jsonb) id`,[revision,JSON.stringify(t)])).rows[0].id;
await assert.rejects(propose(0,{...terms,base_amount_yen:123}),/総額/);
await assert.rejects(propose(0,{...terms,adjustments:[{name:'追加',amount_yen:100}],final_amount_yen:16600}),/追加項目/);
await assert.rejects(propose(0,{...terms,tax_amount_yen:1.5}),/税条件/);
await assert.rejects(propose(0,{...terms,area:'Infinity'}),/有限/);
await assert.rejects(propose(null),/再読込/);
await assert.rejects(propose(0,{...terms,tax_amount_yen:1,final_amount_yen:15001}),/税額/);
await assert.rejects(propose(0,{...terms,mode:'lump_sum',base_amount_yen:' NaN ',final_amount_yen:' NaN '}),/有限/);
await db.exec(`reset role; update companies set postal_code='100-0001',address='東京都千代田区千代田1-1（検証用）',phone='03-0000-0001',fax='03-0000-0002',company_seal_enabled=true where id='${parent}'; set role authenticated;`);
const proposal=await propose(0);
await assert.rejects(propose(0),/再読込/);
await db.query(`select public.confirm_site_payment_terms('${proposal}','${parent}')`);
await db.exec(`set test.uid='${admin2}'`);
await db.query(`select public.confirm_site_payment_terms('${proposal}','${child}')`);
let result=(await db.query(`select public.site_payment_agreement_workspace('${item}','${child}') v`)).rows[0].v;
assert.equal(result.proposals[0].confirmations.length,2);
const original=(await db.query(`select public.saved_site_payment_document('${proposal}','${child}') v`)).rows[0].v;
await db.exec(`reset role; update companies set name='変更名',postal_code='999-9999',address='変更住所',phone='変更電話',fax='変更FAX',company_seal_enabled=false; set role authenticated;`);
assert.deepEqual((await db.query(`select public.saved_site_payment_document('${proposal}','${child}') v`)).rows[0].v,original);
assert.deepEqual(original.terms,terms);
assert.equal(original.snapshot_version,2);
assert.equal(original.parent_postal_code,'100-0001');
assert.equal(original.parent_address,'東京都千代田区千代田1-1（検証用）');
assert.equal(original.parent_phone,'03-0000-0001');
assert.equal(original.parent_fax,'03-0000-0002');
assert.equal(original.parent_company_seal_enabled,true);
await assert.rejects(db.query(`update private.site_payment_proposals set terms='{}'`),/permission denied/);
await db.exec(`set test.uid='${outsider}'`);
await assert.rejects(db.query(`select public.site_payment_agreement_workspace('${item}','${parent}')`),/管理者/);
await db.exec(`set test.uid='${admin1}'`);
const newer=await propose(1,{...terms,mode:'lump_sum',base_amount_yen:20000,final_amount_yen:21500});
await assert.rejects(db.query(`select public.confirm_site_payment_terms('${proposal}','${parent}')`),/古い/);
result=(await db.query(`select public.site_payment_agreement_workspace('${item}','${parent}') v`)).rows[0].v;
await assert.rejects(db.query(`select public.saved_site_payment_document('${newer}','${parent}')`),/双方/);
assert.equal(result.proposals.length,2); assert.equal(result.proposals[0].id,newer); assert.equal(result.proposals[0].confirmations.length,0); assert.deepEqual(result.proposals[1].terms,terms);
if(process.env.SKO_SITE_PAYMENT_OUTPUT_JSON) {
  const snapshots=[original];
  await db.exec(`reset role; update companies set name=case when id='${parent}' then '株式会社青空工業' else '株式会社山田建設' end; update companies set postal_code='160-0022',address='東京都新宿区新宿1-2-3（PDF検証用）',phone='03-0000-0011',fax='03-0000-0012',company_seal_enabled=false where id='${parent}'; update sites set name='都内共同工事現場・外壁改修工事および仮設足場撤去作業'; set role authenticated;`);
  async function confirmAndSave(id) {
    await db.exec(`set test.uid='${admin1}'`);
    await db.query(`select public.confirm_site_payment_terms('${id}','${parent}')`);
    await db.exec(`set test.uid='${admin2}'`);
    await db.query(`select public.confirm_site_payment_terms('${id}','${child}')`);
    return (await db.query(`select public.saved_site_payment_document('${id}','${child}') v`)).rows[0].v;
  }
  snapshots.push(await confirmAndSave(newer));
  const adjustments=[
    {name:'追加工事・養生資材搬入および夜間近隣安全誘導に関する合意額',amount_yen:2000,direction:'addition'},
    {name:'福利厚生費',amount_yen:500,direction:'deduction'},
    {name:'追加資材',amount_yen:800,direction:'addition'},
    {name:'返却資材精算',amount_yen:300,direction:'deduction'},
  ];
  await db.exec(`set test.uid='${admin1}'`);
  const inclusive=await propose(2,{...terms,tax_included:true,adjustments,final_amount_yen:17000});
  snapshots.push(await confirmAndSave(inclusive));
  await db.exec(`set test.uid='${admin1}'`);
  await db.exec(`reset role; update companies set company_seal_enabled=true where id='${parent}'; set role authenticated;`);
  const lump=await propose(3,{...terms,mode:'lump_sum',base_amount_yen:20000,adjustments,final_amount_yen:23500});
  snapshots.push(await confirmAndSave(lump));
  await fs.writeFile(process.env.SKO_SITE_PAYMENT_OUTPUT_JSON,JSON.stringify(snapshots));
  console.log('PASS: four accepted immutable snapshots exported for real Flutter PDF fixtures');
}
await db.exec(`set test.uid='${admin1}'`);
const current=(await db.query(`select public.site_payment_agreement_workspace('${item}','${parent}') v`)).rows[0].v;
const revision=current.proposals[0].revision;
await assert.rejects(propose(revision,{...terms,tax_amount_yen:1400,tax_override_reason:'   ',final_amount_yen:16400}),/税額/);
const manyExtras=Array.from({length:6},(_,i)=>({name:`合意項目${i+1}`,amount_yen:100,direction:i%2?'deduction':'addition'}));
const manualTerms={...terms,adjustments:manyExtras,tax_amount_yen:1400,tax_override_reason:'双方で確認した個別税額の調整',final_amount_yen:16400};
const manual=await propose(revision,manualTerms);
await db.query(`select public.confirm_site_payment_terms('${manual}','${parent}')`);
await db.exec(`set test.uid='${admin2}'`);
await db.query(`select public.confirm_site_payment_terms('${manual}','${child}')`);
const manualSnapshot=(await db.query(`select public.saved_site_payment_document('${manual}','${child}') v`)).rows[0].v;
assert.deepEqual(manualSnapshot.terms,manualTerms);
assert.equal(manualSnapshot.terms.adjustments.length,6);
const history=(await db.query(`select public.site_payment_agreement_workspace('${item}','${child}') v`)).rows[0].v;
assert.deepEqual(history.proposals.find(p=>p.id===proposal).terms,terms);
// Simulate a document saved by the previous deployed contract. Replacing the
// function must not infer today's company details into that existing document.
const legacy={...manualSnapshot};
for(const key of ['snapshot_version','parent_postal_code','parent_address','parent_phone','parent_fax','parent_company_seal_enabled']) delete legacy[key];
await db.exec('reset role');
await db.query(`update private.site_payment_document_snapshots set snapshot=$1::jsonb where proposal_id='${manual}'`,[JSON.stringify(legacy)]);
await db.exec(await fs.readFile(new URL('../supabase/migrations/20261008212855_site_payment_company_snapshot.sql',import.meta.url),'utf8'));
await db.exec('set role authenticated');
assert.deepEqual((await db.query(`select public.saved_site_payment_document('${manual}','${child}') v`)).rows[0].v,legacy);
console.log('PASS: captured company address/contact/seal stay immutable; legacy snapshot stays untouched');
console.log('PASS: six named signed extras and manual tax reason preserved in mutually confirmed immutable snapshot');
console.log('PASS: OFF guard, administrator scope, arithmetic, revision conflict, two-party confirmation, immutable originals, stale confirmation, outsider denial');
if(process.argv.includes('--seal-snapshots')) {
 await db.exec(`reset role;alter table companies add column updated_at timestamptz;
 create table invoices(id uuid primary key,company_id uuid,snapshot jsonb);
 create table payment_certificates(id uuid primary key,company_id uuid,snapshot jsonb);
 create table payroll_statements(id uuid primary key,company_id uuid,detail jsonb);
 create function private.refresh_automatic_invoice(cid uuid,partner uuid,day date) returns void language plpgsql as $$
 declare existing public.invoices; snapshot_value jsonb;
 begin snapshot_value:='{}';if existing.id is null then return;end if;end $$;
 create function private.refresh_automatic_payment_certificate(cid uuid,partner uuid,day date) returns void language plpgsql as $$
 declare existing public.payment_certificates; snapshot_value jsonb;
 begin snapshot_value:='{}';if existing.id is null then return;end if;end $$;
 create function private.payroll_document_metadata(p_statement_id uuid) returns jsonb language sql as $$
 select jsonb_build_object('company_seal_enabled',c.company_seal_enabled,'old',true)
 from payroll_statements ps join companies c on c.id=ps.company_id where ps.id=p_statement_id $$;`);
 await db.exec(await fs.readFile(new URL('../supabase/migrations/20261009011357_company_seal_aoyagi_style.sql',import.meta.url),'utf8'));
 await db.exec(await fs.readFile(new URL('../supabase/migrations/20261009012730_company_seal_document_snapshots.sql',import.meta.url),'utf8'));
 await db.exec(`set test.uid='${admin2}';set role authenticated;`);
 assert.deepEqual((await db.query(`select public.saved_site_payment_document('${manual}','${child}') v`)).rows[0].v,legacy);
 const sealSnapshots=[];
 for(const name of ['株式会社テスト建設','株式会社長い会社名建設工業']) {
  await db.exec(`reset role;update companies set name='${name}',company_seal_style='aoyagi_reisho',company_seal_enabled=true where id='${parent}';set test.uid='${admin1}';set role authenticated;`);
  const workspace=(await db.query(`select public.site_payment_agreement_workspace('${item}','${parent}') v`)).rows[0].v;
  const next=await propose(workspace.proposals[0].revision,manualTerms);
  await db.query(`select public.confirm_site_payment_terms('${next}','${parent}')`);
  await db.exec(`set test.uid='${admin2}'`);
  await db.query(`select public.confirm_site_payment_terms('${next}','${child}')`);
  const captured=(await db.query(`select public.saved_site_payment_document('${next}','${child}') v`)).rows[0].v;
  assert.equal(captured.snapshot_version,3);
  assert.deepEqual(captured.company_seal_snapshot,{version:1,style:'aoyagi_reisho',name});
  await db.exec(`reset role;update companies set name='株式会社変更後',company_seal_style='legacy' where id='${parent}';set role authenticated;`);
  assert.deepEqual((await db.query(`select public.saved_site_payment_document('${next}','${child}') v`)).rows[0].v,captured);
  sealSnapshots.push(captured);
 }
 if(process.env.SKO_SITE_PAYMENT_ALL_VERSIONS_OUTPUT_JSON) await fs.writeFile(process.env.SKO_SITE_PAYMENT_ALL_VERSIONS_OUTPUT_JSON,JSON.stringify([legacy,original,...sealSnapshots]));
 if(process.env.SKO_SITE_PAYMENT_SEAL_OUTPUT_JSON) await fs.writeFile(process.env.SKO_SITE_PAYMENT_SEAL_OUTPUT_JSON,JSON.stringify(sealSnapshots));
 console.log('PASS: actual mutually confirmed v3 snapshots freeze genuine style/name; legacy unchanged; two short/long PDF fixtures exported');
}
await db.close();
