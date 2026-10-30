import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
const original=await readFile('tool/trade_document_form_server_fixture.mjs','utf8');
const metadata=JSON.parse(await readFile('docs/review/trade-document-month-end/deployed-contact-source.json','utf8'));
const marker=' await identity();\n const w=';assert.equal(original.split(marker).length,2);
const unit=`
 await db.exec('alter table public.companies add column phone text,add column fax text,add column email text');
 await db.query('update public.companies set phone=$1,fax=$2 where id=$3',['03-1111-2222','03-3333-4444',company]);
 await db.exec(${JSON.stringify(metadata.rows.find(r=>r.proname==='partner_company_profile_value').definition.trim()+';')});
 await db.exec('revoke all on function private.partner_company_profile_value(uuid) from public,anon,authenticated,service_role');
 await db.exec(await read('docs/review/trade-document-month-end/server-upgrade.sql.review-only'));
 const changed=await pin();const expectedSource=before.find(x=>x.name===(branch==='bank'?'trade_document_source_before_partner_bank':'trade_document_source'));
 assert.equal(expectedSource.body,'ebcc70935938482054943560390038b2');expectedSource.body='f46a4457a520eec9f28bfea30499dd97';
 assert.deepEqual(changed,before);passed++;
`;
const extra=`
 // V1 stays exact: day31 remains numeric, not month_end.
 assert.equal(edited.payload.form_fields.payment_day,31);passed++;
 const secondDocument='20000000-0000-4000-8000-000000000001';
 await db.exec('reset role');await db.query("insert into payment_certificates values($1,$2,$3,'2026-10-01','2026-10-31',1,'draft',null,110000,$4::jsonb,false)",[secondDocument,company,partner,JSON.stringify({tax:10000})]);await identity();
 const save2=(p,v=0)=>q("select public.save_trade_document_attachment('payment_certificate',$1,'1',$2,$3::jsonb) v",[secondDocument,v,JSON.stringify(p)]);
 const cap=await q("select public.trade_document_attachment_workspace('payment_certificate',$1,'1') v",[secondDocument]);
 assert.equal(cap.form_fields_schema_version,2);assert.equal(cap.defaults.issuer.phone,'03-1111-2222');assert.equal(cap.defaults.issuer.fax,'03-3333-4444');passed++;
 const v2={...f,schema:2,progress_cutoff_day:'month_end',issuer_representative_title:'代表取締役',amount_description:'下記「施工単価内訳書」による'};
 const next=await save2({...payload,issuer:{...edited.payload.issuer,phone:cap.defaults.issuer.phone,fax:cap.defaults.issuer.fax},form_fields:v2},0);
 assert.equal(next.payload.form_fields.progress_cutoff_day,'month_end');assert.equal(next.payload.form_fields.issuer_representative_title,'代表取締役');passed++;
 await deny(()=>save2({...next.payload,form_fields:fresh()},1),'40001');
 await deny(()=>save2({...next.payload,issuer:{...next.payload.issuer,phone:'偽の電話'}},1),'22023');
 for(const fields of [{...v2,progress_cutoff_day:'末日'},{...v2,progress_cutoff_day:0},{...v2,progress_cutoff_day:32},{...v2,invoice_cutoff_day:'month_end'},{...v2,issuer_representative_title:'x'.repeat(33)},{...v2,amount_description:'x'.repeat(241)},{...v2,extra:true}])await deny(()=>save2({...next.payload,form_fields:fields},1),'22023');
 const explicit31=await save2({...next.payload,form_fields:{...v2,progress_cutoff_day:31}},1);assert.equal(explicit31.payload.form_fields.progress_cutoff_day,31);passed++;
 console.log(JSON.stringify({pass:true,month_end_and_numeric31_distinct:true,contacts_from_own_company:true,no_downgrade_or_contact_forgery:true}));
`;
// Keep all original negative/source/signed/bank assertions. Run new version cases
// only at the end so their additional version increments cannot mask old CAS checks.
const point=" console.log(JSON.stringify({result:";
assert.ok(original.includes(point));
let code=original.replace("const root=new URL('../',import.meta.url);","const root=new URL("+JSON.stringify(pathToFileURL(process.cwd()+'/').href)+");").replace(marker,unit+marker).replace(point,extra+point);
const folder=await mkdtemp(join(tmpdir(),'trade-month-end-'));
try {const file=join(folder,'fixture.mjs');await writeFile(file,code);
 const r=spawnSync(process.execPath,[file,process.argv[2],process.argv[3]??'core'],{stdio:'inherit',env:process.env});if(r.error)throw r.error;process.exitCode=r.status??1;
} finally {await rm(folder,{recursive:true,force:true});}
