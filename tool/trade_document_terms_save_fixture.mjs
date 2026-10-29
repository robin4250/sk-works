// Isolated exact-SQL fixture only; no production data or schema operations.
import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
export async function verifyTermsSave(db,{id,company,partner,actor,expectedDelegate}){
 const reference={schema:1,version:1,title:'[ 工事請負契約条項 ]',source_sha256:'3acf9090f2c027840bba43351f4d9e173759baa8b7c0340c05db9e28731f0d1f',renderer_contract:'sko-original-form-20261029-v1',design_sha256:'942bad918b696b4c2c527dbf2fca9d050e4fb38a3674cff115eb0755793b8a18'};
 const docs=[id(9501),id(9502),id(9503)];let checks=0;
 const q=async(sql,args)=>(await db.query(sql,args)).rows[0]?.v;
 const deny=async(fn,code)=>{await assert.rejects(fn,error=>error.code===code);checks++;};
 await db.exec('reset role');
 for(const doc of docs)await db.query("insert into public.payment_certificates(id,company_id,partner_company_id,period_start,period_end,revision,status,finalized_at,gross_amount,snapshot,calculation_blocked) values($1,$2,$3,'2026-10-01','2026-10-31',1,'draft',null,110000,'{\"tax\":10000,\"calculation_rows\":[{\"work_content\":\"消費税\",\"amount_yen\":10000}]}',false)",[doc,company,partner]);
 await actor();
 const make=async(doc)=>{const w=await q("select public.trade_document_attachment_workspace('payment_certificate',$1,'1') v",[doc]);return {...w.defaults,issue_date:'2026-09-15',work_name:'確定条項の検証工事',work_address:'東京都',intro_text:'工事を発注',payment_conditions:'完了後支払い',notes:'',tax_amount_yen:10000};};
 const save=(doc,version,payload)=>q("select public.save_trade_document_attachment('payment_certificate',$1,'1',$2,$3::jsonb) v",[doc,version,JSON.stringify(payload)]);
 const payload={...await make(docs[0]),contract_terms:reference};
 for(const invalid of [null,{...reference,version:2},{...reference,source_sha256:'0'.repeat(64)},{...reference,title:'別題名'},{...reference,extra:true},{...reference,renderer_contract:'unknown'},{...reference,design_sha256:'0'.repeat(64)}])await deny(()=>save(docs[2],0,{...payload,contract_terms:invalid}),'22023');
 const first=await save(docs[0],0,payload);assert.deepEqual(first.payload.contract_terms,reference);checks++;
 const omitted={...first.payload};delete omitted.contract_terms;
 for(const invalid of [omitted,{...first.payload,contract_terms:null},{...first.payload,contract_terms:{...reference,source_sha256:'0'.repeat(64)}}])await deny(()=>save(docs[0],1,invalid),'40001');
 const edited=await save(docs[0],1,{...first.payload,notes:'明示した通常編集'});assert.equal(edited.version,2);assert.deepEqual(edited.payload.contract_terms,reference);checks++;
 const legacy=await save(docs[1],0,await make(docs[1]));assert.equal(Object.hasOwn(legacy.payload,'contract_terms'),false);checks++;
 await deny(()=>save(docs[1],1,{...legacy.payload,contract_terms:reference}),'40001');
 await deny(()=>save(docs[2],0,{...payload,unrelated_blob:'x'.repeat(16384)}),'22023');
 const delegate=await q("select jsonb_build_object('hash',md5(prosrc),'owner',pg_get_userbyid(proowner),'security',prosecdef,'config',proconfig,'acl',proacl::text) v from pg_proc where oid='private.save_trade_document_before_confirmed_terms(text,uuid,text,integer,jsonb)'::regprocedure");
 assert.deepEqual(delegate,{hash:expectedDelegate,owner:'postgres',security:true,config:['search_path=""'],acl:'{postgres=X/postgres}'});checks++;
 await db.exec('reset role');
 // Remove only the three synthetic parents created above before the surrounding
 // fixture compares its original financial rows. No real or pre-existing row.
 await db.query("delete from private.trade_document_attachments where subject_kind='payment_certificate' and subject_id=any($1::uuid[])",[docs]);
 await db.query('delete from public.payment_certificates where id=any($1::uuid[])',[docs]);
 await deny(async()=>db.exec(await fs.readFile('docs/review/trade-document-terms/save-guard.sql.review-only','utf8')),'55000');await db.exec('rollback');
 await deny(async()=>db.exec(await fs.readFile('docs/review/partner-company-bank-order/order-snapshot.sql.review-only','utf8')),'55000');await db.exec('rollback');
 await actor();
 console.log(JSON.stringify({result:'PASS immutable confirmed terms save contract',checks,expectedDelegate,real_auth:false,production_changes:false}));
}
