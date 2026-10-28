// Review-only composition over private temporary copies. Canonical fixtures stay
// byte-identical so other exact-source suites retain their independent anchors.
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
const root=fileURLToPath(new URL('../',import.meta.url));
const manifest=JSON.parse(await fs.readFile(new URL('./fixtures/trade_reciprocal_gate/source_manifest.json',import.meta.url),'utf8'));
const temp=await fs.mkdtemp(path.join(os.tmpdir(),'sko-notice-seal-fixture-'));
const exact=async name=>{
 const relative='tool/'+name,b=await fs.readFile(path.join(root,relative));
 const expected=manifest.files.find(row=>row.path===relative)?.sha;
 const actual=createHash('sha1').update(Buffer.concat([Buffer.from(`blob ${b.length}\0`),b])).digest('hex');
 if(!expected||actual!==expected)throw Error('canonical composition fixture differs: '+relative);
 return b.toString();
};
try{
 await fs.mkdir(path.join(temp,'tool'));await fs.mkdir(path.join(temp,'supabase/migrations'),{recursive:true});
 const names=['verify_trade_document_bound_seal_consent.mjs','trade_document_invoice_confirmation_fixture.mjs','trade_document_invoice_confirmation_races.mjs'];
 for(const name of names){
  let source=await exact(name);
  if(name==='trade_document_invoice_confirmation_fixture.mjs'){
   // Only extension invoices use a closed synthetic month; existing canonical
   // suite invoices and its race fixtures retain their original dates.
   const original=`'2026-10-01','2026-10-31',clock_timestamp(),'draft',110000,10000,'{}')",[parent,A,CUSTOMER]);`;
   if(source.split(original).length!==2)throw Error('invoice fixture date anchor changed');
   source=source.replace(original,`$4::date,$5::date,clock_timestamp(),'draft',110000,10000,'{}')",[parent,A,CUSTOMER,[21,22,23,24].includes(num)?'2020-10-01':'2026-10-01',[21,22,23,24].includes(num)?'2020-10-31':'2026-10-31']);`);
   const anchor=" console.log('PASS invoice adapter:";
   if(source.split(anchor).length!==2)throw Error('composition finish anchor changed');
   // Run after the unchanged native suite, not before it. This extension must not
   // influence pre-existing race requests, settings or evidence counts.
   source=source.replace(anchor," await (await import('./trade_document_notice_seal_fixture.mjs')).verifyNoticeSeal(db,{...c,prepare,preview,state});\n"+anchor);
  }
  await fs.writeFile(path.join(temp,'tool',name),source);
 }
 await fs.copyFile(path.join(root,'tool/trade_document_notice_seal_fixture.mjs'),path.join(temp,'tool/trade_document_notice_seal_fixture.mjs'));
 await fs.copyFile(path.join(root,'tool/trade_document_notice_source_integrity_fixture.mjs'),path.join(temp,'tool/trade_document_notice_source_integrity_fixture.mjs'));
 await fs.copyFile(path.join(root,'tool/trade_document_notice_adjustment_provider_fixture.mjs'),path.join(temp,'tool/trade_document_notice_adjustment_provider_fixture.mjs'));
 await fs.copyFile(path.join(root,'tool/trade_document_notice_expense_provider_fixture.mjs'),path.join(temp,'tool/trade_document_notice_expense_provider_fixture.mjs'));
 await fs.copyFile(path.join(root,'tool/trade_document_notice_daily_preview_fixture.mjs'),path.join(temp,'tool/trade_document_notice_daily_preview_fixture.mjs'));
 await fs.copyFile(path.join(root,'tool/trade_document_notice_calculated_confirmation_fixture.mjs'),path.join(temp,'tool/trade_document_notice_calculated_confirmation_fixture.mjs'));
 await fs.copyFile(path.join(root,'supabase/migrations/20261014124714_monthly_trade_document_attachment.sql'),path.join(temp,'supabase/migrations/20261014124714_monthly_trade_document_attachment.sql'));
 if(process.argv[2]==='--check-generated'){
  for(const name of [...names,'trade_document_notice_seal_fixture.mjs','trade_document_notice_source_integrity_fixture.mjs','trade_document_notice_daily_preview_fixture.mjs','trade_document_notice_calculated_confirmation_fixture.mjs','trade_document_notice_adjustment_provider_fixture.mjs','trade_document_notice_expense_provider_fixture.mjs']){
   const checked=spawnSync(process.execPath,['--check',path.join(temp,'tool',name)],{encoding:'utf8'});
   if(checked.status!==0)throw Error(checked.stderr);
  }
  console.log('PASS exact canonical composition sources and private generated syntax');
 }else{
  const env={...process.env};
  for(const key of ['SKO_NOTICE_SEAL_REVIEW_HOOK','SKO_MONTHLY_PAYMENT_REVIEW_HOOK','SKO_TRADE_DOCUMENT_API_REVIEW_HOOK','SKO_TRADE_DOCUMENT_REAL_AUTH_HOOK'])delete env[key];
  const result=spawnSync(process.execPath,[path.join(temp,'tool/verify_trade_document_bound_seal_consent.mjs'),...process.argv.slice(2)],{cwd:root,stdio:'inherit',env});
  if(result.error)throw result.error;process.exitCode=result.status??1;
 }
}finally{await fs.rm(temp,{recursive:true,force:true});}
