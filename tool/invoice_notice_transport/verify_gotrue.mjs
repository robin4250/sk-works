// Reuse immutable canonical fixtures in private temporary source copies.
import fs from 'node:fs/promises';import path from 'node:path';import os from 'node:os';
import {pathToFileURL,fileURLToPath} from 'node:url';import {createHash} from 'node:crypto';import {spawnSync} from 'node:child_process';
const root=fileURLToPath(new URL('../../',import.meta.url));
const temp=await fs.mkdtemp(path.join(os.tmpdir(),'sko-invoice-transport-'));
const url=p=>pathToFileURL(path.join(root,p)).href;
function replace(source,old,value){if(source.split(old).length!==2)throw Error('invoice transport source anchor changed');return source.replace(old,()=>value);}
try{
 const manifest=JSON.parse(await fs.readFile(path.join(root,'tool/fixtures/trade_reciprocal_gate/source_manifest.json'),'utf8'));
 const exact=async p=>{const bytes=await fs.readFile(path.join(root,p));const actual=createHash('sha1').update(Buffer.concat([Buffer.from(`blob ${bytes.length}\0`),bytes])).digest('hex');if(manifest.files.find(x=>x.path===p)?.sha!==actual)throw Error('canonical invoice source differs');return bytes.toString();};
 let verify=await exact('tool/verify_trade_document_bound_seal_consent.mjs');
 verify=replace(verify,"new URL('../supabase/migrations/20261014124714_monthly_trade_document_attachment.sql',import.meta.url)",`new URL(${JSON.stringify(url('supabase/migrations/20261014124714_monthly_trade_document_attachment.sql'))})`);
 verify=replace(verify,"'./trade_document_auth_fixture_context.mjs'",JSON.stringify(url('tool/trade_document_auth_fixture_context.mjs')));
 verify=replace(verify,"'./trade_document_invoice_confirmation_fixture.mjs'",JSON.stringify(pathToFileURL(path.join(temp,'invoice.mjs')).href));
 // Monthly hook is disabled in this dedicated invoice runner.
 verify=replace(verify,"'./trade_document_monthly_review_fixture.mjs'",JSON.stringify(url('tool/trade_document_monthly_review_fixture.mjs')));
 await fs.writeFile(path.join(temp,'verify.mjs'),verify,{mode:0o600});
 let invoice=await exact('tool/trade_document_invoice_confirmation_fixture.mjs');
 invoice=replace(invoice,"'2026-10-01','2026-10-31',clock_timestamp(),'draft',110000,10000,'{}')\",[parent,A,CUSTOMER]);", "$4::date,$5::date,clock_timestamp(),'draft',110000,10000,'{}')\",[parent,A,CUSTOMER,num===21?'2020-10-01':'2026-10-01',num===21?'2020-10-31':'2026-10-31']);");
 invoice=replace(invoice," console.log('PASS invoice adapter:",` await (await import(${JSON.stringify(pathToFileURL(path.join(temp,'notice.mjs')).href)})).verifyNoticeSeal(db,{...c,prepare,preview,state});\n console.log('PASS invoice adapter:`);
 await fs.writeFile(path.join(temp,'invoice.mjs'),invoice,{mode:0o600});
 let notice=await fs.readFile(path.join(root,'tool/trade_document_notice_seal_fixture.mjs'),'utf8');
 const cut=notice.indexOf(' const x=await prepare(21)');if(cut<0||notice.indexOf(' const x=await prepare(21)',cut+1)>=0)throw Error('notice setup anchor changed');notice=notice.slice(0,cut);
 const reauth=await fs.readFile(path.join(root,'tool/staged/reauthentication_proofs.sql'),'utf8');
 const functionStart=reauth.indexOf('create function private.require_reauthentication_session()'),functionEnd=reauth.indexOf('end $$;',functionStart);
 if(functionStart<0||functionEnd<0)throw Error('canonical live-session function absent');
 const liveGate=reauth.slice(functionStart,functionEnd+7);
 // Fixture barrier-key adapter only; the sensitive helper body is verbatim.
 const barrier="create function private.account_deletion_barrier_key(p_actor uuid)returns bigint language sql immutable as $$select hashtextextended('deletion:'||p_actor::text,0)$$;";
 notice=replace(notice,"create function private.require_reauthentication_session()returns uuid language sql as $$select nullif(current_setting('test.notice_sid',true),'')::uuid$$;",barrier+liveGate+'revoke all on function private.require_reauthentication_session() from public,anon,authenticated,service_role;');
 notice=replace(notice,' const sid=id(9001);'," const sid=await q(\"select (auth.jwt()->>'session_id')::uuid v\");");
 notice+=` await (await import(${JSON.stringify(url('tool/invoice_notice_transport/fixture.mjs'))})).verifyInvoiceNoticeTransport(db,{...c,prepare,preview,state,issue});\n}\n`;
 await fs.writeFile(path.join(temp,'notice.mjs'),notice,{mode:0o600});
 let runner=await fs.readFile(path.join(root,'tool/trade_document_auth_api_gotrue_e2e.mjs'),'utf8');
 runner=replace(runner,"'./trade_document_auth_fixture_context.mjs'",JSON.stringify(url('tool/trade_document_auth_fixture_context.mjs')));
 runner=replace(runner,"process.env.SKO_MONTHLY_PAYMENT_REVIEW_HOOK='contract-v1';",'delete process.env.SKO_MONTHLY_PAYMENT_REVIEW_HOOK;');
 runner=replace(runner,"process.argv[3]='auth-http-setup';await import('./verify_trade_document_bound_seal_consent.mjs');",`await (await import(${JSON.stringify(url('tool/invoice_notice_transport/fixture.mjs'))})).installInvoiceNoticeTransportContext({api,publicKey,database,pg,tokens,users,password,request});process.argv[3]='auth-http-setup';await import(${JSON.stringify(pathToFileURL(path.join(temp,'verify.mjs')).href)});`);
 const start=runner.indexOf(" phase='install-public-api';"),end=runner.indexOf('}catch(error)');if(start<0||end<start)throw Error('Auth runner finish anchor changed');
 runner=runner.slice(0,start)+" assert.deepEqual(await authFns(),originalAuthFns);console.log('PASS unchanged real auth.uid/auth.jwt functions, local-only invoice transport chain; no public API/grant installation');\n"+runner.slice(end);
 await fs.writeFile(path.join(temp,'runner.mjs'),runner,{mode:0o600});
 for(const file of ['verify.mjs','invoice.mjs','notice.mjs','runner.mjs']){const checked=spawnSync(process.execPath,['--check',path.join(temp,file)],{encoding:'utf8'});if(checked.status!==0)throw Error(checked.stderr);}
 if(process.argv[2]==='--check-generated'){console.log('PASS exact canonical invoice sources/private generated transport syntax');}
 else{if(process.env.SKO_INVOICE_NOTICE_TRANSPORT_HOOK!=='contract-v1')throw Error('explicit invoice transport fixture hook required');const result=spawnSync(process.execPath,[path.join(temp,'runner.mjs')],{cwd:root,stdio:'inherit',env:process.env});if(result.error)throw result.error;process.exitCode=result.status??1;}
}finally{await fs.rm(temp,{recursive:true,force:true});}
