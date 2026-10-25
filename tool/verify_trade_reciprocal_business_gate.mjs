// Reuse exact canonical public-role fixture; modify private temporary copies only.
import fs from 'node:fs/promises';import path from 'node:path';import os from 'node:os';
import {fileURLToPath} from 'node:url';import {createHash} from 'node:crypto';import {spawnSync} from 'node:child_process';
const root=fileURLToPath(new URL('../',import.meta.url));
const manifest=JSON.parse(await fs.readFile(new URL('./fixtures/trade_reciprocal_gate/source_manifest.json',import.meta.url),'utf8'));
const temp=await fs.mkdtemp(path.join(os.tmpdir(),'sko-trade-gated-fixture-'));
const check=async p=>{const b=await fs.readFile(path.join(root,p));const expected=manifest.files.find(x=>x.path===p)?.sha;if(!expected||createHash('sha1').update(Buffer.concat([Buffer.from(`blob ${b.length}\0`),b])).digest('hex')!==expected)throw Error('exact canonical fixture source differs: '+p);return b.toString();};
try{
 for(const input of manifest.files)await check(input.path);
 await fs.mkdir(path.join(temp,'tool'));await fs.mkdir(path.join(temp,'supabase/migrations'),{recursive:true});
 const modules=['verify_trade_document_bound_seal_consent.mjs','trade_document_invoice_confirmation_fixture.mjs','trade_document_invoice_confirmation_races.mjs','trade_document_monthly_review_fixture.mjs','trade_document_confirmation_api_fixture.mjs'];
 for(const name of modules){let source=await check('tool/'+name);
  if(name==='trade_document_confirmation_api_fixture.mjs'){
   const anchor=" await db.exec(await fs.readFile('docs/candidates/trade_document_confirmation_api_20261022.sql.review-only','utf8'));";
   if(source.split(anchor).length!==2)throw Error('canonical fixture install anchor changed');
   source=source.replace(anchor,anchor+'\n'+await fs.readFile(new URL('./fixtures/trade_reciprocal_gate/setup.mjs.fragment',import.meta.url),'utf8'));
   const finish=' if(process.env.SKO_TRADE_DOCUMENT_API_EXPORT){';
   if(source.split(finish).length!==2)throw Error('canonical fixture final anchor changed');
   source=source.replace(finish,await fs.readFile(new URL('./fixtures/trade_reciprocal_gate/assertions.mjs.fragment',import.meta.url),'utf8')+'\n'+finish);
   const nativeAnchor=" if(c.openNativePeer)await (await import('./trade_document_confirmation_api_races.mjs')).verifyPublicConfirmationApiRaces(db,c);";
   if(source.split(nativeAnchor).length!==2)throw Error('canonical Native race anchor changed');
   // OFF diagnostics precede the unchanged ON Native regression suite. Restore
   // ON only as fixture owner; always finish OFF, including a failed race suite.
   source=source.replace(nativeAnchor,`
 if(c.openNativePeer)await db.exec("update private.master_feature_settings set enabled=true where feature_key='trade_document_reciprocal_seals'");
 try{${nativeAnchor}}
 finally{
  await db.exec("reset role;update private.master_feature_settings set enabled=false where feature_key='trade_document_reciprocal_seals'");
  check(await q("select enabled v from private.master_feature_settings where feature_key='trade_document_reciprocal_seals'"),false);
  console.log('PASS reciprocal fixture final feature OFF after canonical ON Native phase');
 }
 `);
  }
  await fs.writeFile(path.join(temp,'tool',name),source);
 }
 // Native-only race module already belongs to main, not duplicated in the diff.
 await fs.copyFile(path.join(root,'tool/trade_document_confirmation_api_races.mjs'),path.join(temp,'tool/trade_document_confirmation_api_races.mjs'));
 await fs.copyFile(path.join(root,'supabase/migrations/20261014124714_monthly_trade_document_attachment.sql'),path.join(temp,'supabase/migrations/20261014124714_monthly_trade_document_attachment.sql'));
 if(process.argv[2]==='--check-generated'){
  for(const name of modules){const checked=spawnSync(process.execPath,['--check',path.join(temp,'tool',name)],{encoding:'utf8'});if(checked.status!==0)throw Error(checked.stderr);}
  console.log('PASS exact-source manifest and generated module syntax; no database, Auth or business operation executed');
 }else{
 const result=spawnSync(process.execPath,[path.join(temp,'tool/verify_trade_document_bound_seal_consent.mjs'),...process.argv.slice(2)],{cwd:root,stdio:'inherit',env:{...process.env,SKO_MONTHLY_PAYMENT_REVIEW_HOOK:'contract-v1',SKO_TRADE_DOCUMENT_API_REVIEW_HOOK:'contract-v1'}});
 if(result.error)throw result.error;process.exitCode=result.status??1;
 }
}finally{await fs.rm(temp,{recursive:true,force:true});}
