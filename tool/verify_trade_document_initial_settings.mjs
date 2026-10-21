import fs from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
const original = new URL('./verify_trade_document_attachment.mjs', import.meta.url);
let script = await fs.readFile(original, 'utf8');
script = script.replaceAll('import.meta.url', JSON.stringify(original.href));
script = script.replace('const db=new PGlite();', 'const db=globalThis.__tradeSettingsFixtureDb=new PGlite();').replace('await db.close();','');
if (process.argv[2] && !process.argv[2].startsWith('file:')) process.argv[2]=pathToFileURL(process.argv[2]).href;
const marker = "console.log('PASS monthly appendices:";
if (script.split(marker).length !== 2) throw Error('Original fixture final marker changed');
const checks = `
await db.exec(\`reset role;set test.uid='\${a}';set test.invoice_manage='true';set test.invoice_view='true';set test.blocked='false'\`);
const configCatalog=async()=> (await db.query(\`select proname,to_jsonb(p)-'prosrc' metadata from pg_proc p where p.oid in ('private.trade_document_template(text,uuid,integer,jsonb)'::regprocedure,'private.trade_document_attachment_workspace(text,uuid,text)'::regprocedure) order by proname\`)).rows;
const configBefore=await configCatalog();
const financialBefore=(await db.query(\`select (select jsonb_agg(to_jsonb(x)) from public.invoices x) invoices,(select jsonb_agg(to_jsonb(x)) from public.payment_certificates x) certificates,(select jsonb_agg(to_jsonb(x)) from private.trade_document_attachments x) appendices\`)).rows;
const candidate=await fs.readFile(new URL('../docs/candidates/trade_document_initial_settings_20261021.sql.review-only',${JSON.stringify(original.href)}),'utf8');
await db.exec(candidate);
assert.deepEqual(await configCatalog(),configBefore);
const revision=(await db.query('select updated_at::text v from public.invoices where id=$1',[inv])).rows[0].v;
await db.exec('set role authenticated');
const configCall=async(kind,version,payload)=> (await db.query('select public.trade_document_template($1,$2,$3,$4) result',[kind,c,version,payload])).rows[0].result;
const baseOrder=await configCall('payment_certificate',null,null);
const orderConfig=await configCall('payment_certificate',baseOrder.version,{work_name:'共通の初期工事',work_address:'共通の初期場所',auto_generate:false,notes:'設定文'});
assert.equal(orderConfig.settings_contract_version,2);
const inherited=await configCall('invoice',null,null);
assert.equal(inherited.payload.work_name,'共通の初期工事');
assert.equal(inherited.payload.work_address,'共通の初期場所');
assert.equal(inherited.payload.auto_generate,undefined); // order auto switch never controls invoices.
const invoiceConfig=await configCall('invoice',inherited.version,{work_name:'請書の明示工事',work_address:'',auto_generate:false});
assert.equal(invoiceConfig.payload.work_name,'請書の明示工事');assert.equal(invoiceConfig.payload.work_address,'');
const invoiceWorkspace=await call('invoice',inv,revision);
assert.equal(invoiceWorkspace.template.work_name,'請書の明示工事');assert.equal(invoiceWorkspace.template.work_address,'');assert.equal(invoiceWorkspace.template.auto_generate,false);assert.equal(invoiceWorkspace.auto_generate,false);
await db.exec("set test.invoice_manage='false'");
const viewerWorkspace=await call('invoice',inv,revision);assert.deepEqual(viewerWorkspace.template,{});assert.equal(viewerWorkspace.auto_generate,false);
await db.exec("set test.invoice_manage='true'");
for(const payload of [{auto_generate:'false'},{auto_generate:null},{work_name:'x'.repeat(241)},{work_address:'x'.repeat(241)},{total_amount_yen:0},{issuer:{name:'forged'}}]) await assert.rejects(configCall('invoice',invoiceConfig.version,payload));
await assert.rejects(configCall('invoice',inherited.version,{work_name:'stale'}),/再読込/);
const oldInvoice=await configCall('invoice',invoiceConfig.version,{notes:'legacy prose only'});
assert.equal(oldInvoice.payload.work_name,'請書の明示工事');assert.equal(oldInvoice.payload.work_address,'');assert.equal(oldInvoice.payload.auto_generate,false);
const oldOrder=await configCall('payment_certificate',orderConfig.version,{notes:'legacy order prose'});
assert.equal(oldOrder.payload.auto_generate,false);assert.equal(oldOrder.payload.work_name,undefined);assert.equal(oldOrder.payload.work_address,undefined); // preserve pre-existing payment clear semantics.

await db.exec('reset role');
assert.deepEqual((await db.query(\`select (select jsonb_agg(to_jsonb(x)) from public.invoices x) invoices,(select jsonb_agg(to_jsonb(x)) from public.payment_certificates x) certificates,(select jsonb_agg(to_jsonb(x)) from private.trade_document_attachments x) appendices\`)).rows,financialBefore);
assert.deepEqual(await configCatalog(),configBefore);
await assert.rejects(db.exec(candidate),/source drift/);await db.exec('rollback');
console.log('PASS initial settings: invoice/order work defaults, inherited first text, explicit clear, independent automatic flags, exact original guards, CAS, metadata and saved financial/appendix preservation');
`;
script=script.replace(marker,()=>checks+'\n'+marker);
try { await import('data:text/javascript;base64,'+Buffer.from(script).toString('base64')); } finally { await globalThis.__tradeSettingsFixtureDb?.close(); }
