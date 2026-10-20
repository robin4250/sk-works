// Reuse the existing appendix fixture with a disposable PGlite or guarded PostgreSQL adapter.
import fs from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
const flavor=process.argv[3];
if(flavor!==undefined&&!['base','tax'].includes(flavor))throw new Error('Unknown source flavor; expected base or tax.');
const flavors=flavor===undefined?[false,true]:[flavor==='tax'];
const fixture=new URL('./verify_trade_document_attachment.mjs',import.meta.url);
if(!process.argv[2])throw new Error('Pass the disposable database adapter module path.');
process.argv[2]=pathToFileURL(process.argv[2]).href;
const original=await fs.readFile(fixture,'utf8');
const marker="console.log('PASS monthly appendices";
if(original.split(marker).length!==2)throw new Error('appendix fixture anchor changed');
for(const taxFallback of flavors){
 let script=original.replaceAll('import.meta.url',JSON.stringify(fixture.href));
 const check=`
 await db.exec("reset role");await db.query("select set_config('test.uid',$1,false)",[a]);
 await db.exec('create table public.trade_companies(id uuid primary key,company_id uuid,partner_company_id uuid,trade_role text,address text,corporate_number text,representative_name text)');
 const candidate=await fs.readFile(new URL('../docs/candidates/payment_order_directory_party_source_20261021.sql.review-only',${JSON.stringify(fixture.href)}),'utf8');
 ${taxFallback ? `await db.exec(await fs.readFile(new URL('../docs/candidates/payment_order_tax_from_snapshot_20261020.sql.review-only',${JSON.stringify(fixture.href)}),'utf8'));` : ''}
 const sourceMetaSql="select to_jsonb(p)-'prosrc' metadata from pg_proc p where p.oid='private.trade_document_source(text,uuid,text)'::regprocedure";
 const beforeSourceMeta=(await db.query(sourceMetaSql)).rows;
 const savedBefore=await call('payment_certificate',pc,'2');
 const invoiceBefore=await call('invoice',inv,'2026-10-14T13:00:00Z');
 const appendicesBefore=(await db.query('select to_jsonb(a) row from private.trade_document_attachments a order by subject_kind,subject_id')).rows;
 const tablesBefore=(await db.query('select to_jsonb(p) row from payment_certificates p order by id')).rows;
 // Even same-name/contact foreign or different-partner rows must never be chosen.
 const rowId=n=>'10000000-0000-0000-0000-'+String(n).padStart(12,'0');
 const addDirectory=(id,company,partner,role,address,corp,rep)=>db.query('insert into trade_companies values($1,$2,$3,$4,$5,$6,$7)',[rowId(id),company,partner,role,address,corp,rep]);
 await addDirectory(1,c2,p,'subcontractor','foreign-secret','foreign-corp','foreign-rep');
 await addDirectory(2,c,'10000000-0000-0000-0000-999999999999','subcontractor','wrong-target','wrong-corp','wrong-rep');
 await db.exec('grant execute on function private.trade_document_source(text,uuid,text) to authenticated');
 await assert.rejects(db.exec(candidate),e=>e.code==='55000');await db.exec('rollback');
 await db.exec('revoke execute on function private.trade_document_source(text,uuid,text) from authenticated');
 assert.deepEqual((await db.query(sourceMetaSql)).rows,beforeSourceMeta);
 await db.exec(candidate);
 assert.deepEqual((await db.query(sourceMetaSql)).rows,beforeSourceMeta);
 const unchangedNew=await call('payment_certificate',pc2,'1');
 assert.equal(unchangedNew.defaults.counterparty.corporate_number,'');
 assert.equal(unchangedNew.defaults.counterparty.address,'神奈川');
 await addDirectory(3,c,p,'subcontractor','登録した住所','1234567890123','登録した代表者');
 const configured=await call('payment_certificate',pc2,'1');
 assert.deepEqual(configured.defaults.counterparty,{name:'下請け',address:'登録した住所',corporate_number:'1234567890123',representative_name:'登録した代表者'});
 assert.equal(configured.source_fingerprint,unchangedNew.source_fingerprint);
 // Every adopted field must fit the existing appendix save contract, independently.
 const validAddress='住'.repeat(240),validRepresentative='代'.repeat(80),validCorporate='1234567890123';
 const fieldCases=[
  [validAddress,validCorporate,validRepresentative,validAddress,validCorporate,validRepresentative],
  ['住'.repeat(241),validCorporate,validRepresentative,'神奈川',validCorporate,validRepresentative],
  [validAddress,validCorporate,'代'.repeat(81),validAddress,validCorporate,'乙代表'],
  ...['123456789012','12345678901234','１２３４５６７８９０１２３','123456789012A'].map(corp=>[validAddress,corp,validRepresentative,validAddress,'',validRepresentative]),
  ['住'.repeat(241),'１２３４５６７８９０１２３','代'.repeat(81),'神奈川','','乙代表'],
  ['  '+validAddress+'  ',' '+validCorporate+' ',' '+validRepresentative+' ',validAddress,validCorporate,validRepresentative],
 ];
 for(const [address,corp,rep,expectedAddress,expectedCorp,expectedRep] of fieldCases){
  await db.query('update trade_companies set address=$1,corporate_number=$2,representative_name=$3 where id=$4',[address,corp,rep,rowId(3)]);
  const defaults=(await call('payment_certificate',pc2,'1')).defaults;
  assert.deepEqual(defaults.counterparty,{name:'下請け',address:expectedAddress,corporate_number:expectedCorp,representative_name:expectedRep});
  const validPayload={...defaults,issue_date:'2026-10-15',work_name:'当月工事',work_address:'東京都',payment_conditions:'翌月末',notes:'',tax_amount_yen:20000,
   issuer:{...defaults.issuer,representative_name:'甲代表'}};
  await db.exec('begin');
  const savedFieldCase=(await save(validPayload,0,pc2,'1')).rows[0].result;
  assert.deepEqual(savedFieldCase.payload.counterparty,defaults.counterparty,'supplemented fields must pass the existing save normalizer');
  await db.exec('rollback');
 }
 await db.query("update trade_companies set address='登録した住所',corporate_number='1234567890123',representative_name='登録した代表者' where id=$1",[rowId(3)]);
 console.log('PASS directory party validation: 240/80/13 limits, oversized/invalid/fullwidth fallback, independent valid fields and actual appendix saves');

 assert.deepEqual(await call('payment_certificate',pc,'2'),savedBefore,'saved workspace ignores current directory enrichment');
 assert.deepEqual(await call('invoice',inv,'2026-10-14T13:00:00Z'),invoiceBefore,'invoice output is unchanged');
 await db.query("select set_config('test.uid',$1,false)",[m]);
 const manager=await call('payment_certificate',pc2,'1');
 assert.equal(manager.defaults.counterparty.corporate_number,'');
 assert.equal(manager.defaults.counterparty.representative_name,'乙代表');
 assert.equal(manager.defaults.counterparty.address,'神奈川');
 for(const actor of [v,o]){await db.exec(\`set test.uid='\${actor}'\`);await assert.rejects(call('payment_certificate',pc2,'1'),e=>e.code==='42501');}
 await db.query("select set_config('test.uid',$1,false)",[a]);
 await db.query("update trade_companies set address=' ',corporate_number='',representative_name=null where id=$1",[rowId(3)]);
 const blank=await call('payment_certificate',pc2,'1');
 assert.equal(blank.defaults.counterparty.address,'神奈川');assert.equal(blank.defaults.counterparty.representative_name,'乙代表');assert.equal(blank.defaults.counterparty.corporate_number,'');
 await db.query("update trade_companies set trade_role='both' where id=$1",[rowId(3)]);await call('payment_certificate',pc2,'1');
 await db.query("update trade_companies set trade_role='customer' where id=$1",[rowId(3)]);
 assert.deepEqual((await call('payment_certificate',pc2,'1')).defaults.counterparty,unchangedNew.defaults.counterparty,'wrong-role/ambiguous directory mapping must not supplement or block a document');
 await db.query("update trade_companies set trade_role='subcontractor' where id=$1",[rowId(3)]);
 await addDirectory(4,c,p,'both','ambiguous','ambiguous-corp','ambiguous-rep');
 assert.deepEqual((await call('payment_certificate',pc2,'1')).defaults.counterparty,unchangedNew.defaults.counterparty,'wrong-role/ambiguous directory mapping must not supplement or block a document');
 assert.deepEqual(await call('payment_certificate',pc,'2'),savedBefore,'ambiguity must not block saved output');
 assert.deepEqual((await db.query('select to_jsonb(a) row from private.trade_document_attachments a order by subject_kind,subject_id')).rows,appendicesBefore);
 assert.deepEqual((await db.query('select to_jsonb(p) row from payment_certificates p order by id')).rows,tablesBefore);
 // Explicit user save freezes the new supplemental party; later directory changes never rewrite it.
 await db.query('delete from trade_companies where id=$1',[rowId(4)]);
 await db.query("update trade_companies set address='登録した住所',corporate_number='1234567890123',representative_name='登録した代表者' where id=$1",[rowId(3)]);
 const freshDefaults=(await call('payment_certificate',pc2,'1')).defaults;
 const newPayload={...freshDefaults,issue_date:'2026-10-15',work_name:'当月工事',work_address:'東京都',payment_conditions:'翌月末',notes:'',tax_amount_yen:20000,
 issuer:{...freshDefaults.issuer,representative_name:'甲代表'}};
 const newSaved=(await save(newPayload,0,pc2,'1')).rows[0].result;
 assert.equal(newSaved.payload.counterparty.corporate_number,'1234567890123');
 assert.equal(newSaved.payload.counterparty.representative_name,'登録した代表者');
 await db.query("update trade_companies set corporate_number='9999999999999',representative_name='後日の変更' where id=$1",[rowId(3)]);
 assert.deepEqual((await call('payment_certificate',pc2,'1')).attachment,newSaved);
 await assert.rejects(db.exec(candidate),e=>e.code==='55000');await db.exec('rollback');
 console.log('PASS payment order directory supplement (${taxFallback ? 'tax fallback source' : 'base source'}): exact scope/role, foreign ignored, one mapping, blank fallback, manager unchanged, saved+invoice+finance unchanged, ambiguity refused, metadata preserved');
 `;
 script=script.replace(marker,()=>check+'\n'+marker);
 try {await import('data:text/javascript;base64,'+Buffer.from(script).toString('base64')+'#'+String(taxFallback));}
 catch(error){console.error(error.name+': '+error.message.split(' from \"data:')[0]);process.exitCode=1;break;}
}
