// Offline experiment only: no listener, DB, credentials or network permission.
import {createCanonicalWasmRenderer} from './build/runtime.mjs';
import process from 'node:process';
const selected=Deno.args[0]??'all';
const names=['order-v1','order-v2','acceptance-v1','acceptance-v2'];
if(selected!=='all'&&!names.includes(selected))throw Error('fixed_case_required');
const cpu=()=>{try{return process.cpuUsage();}catch{return null;}};
const elapsed=(before,after)=>before&&after?{user_us:after.user-before.user,system_us:after.system-before.system}:null;
const started=performance.now(),startCpu=cpu();
const render=await createCanonicalWasmRenderer();
const boot={wall_ms:performance.now()-started,cpu:elapsed(startCpu,cpu()),memory:Deno.memoryUsage()};
if(typeof render!=='function'||'skoCanonicalPdfRender' in globalThis)throw Error('private_export_required');
const cases=JSON.parse(await Deno.readTextFile(new URL('./build/cases.json',import.meta.url)));
const results=[];
for(const name of names.filter(n=>selected==='all'||n===selected)){
 const before=performance.now(),beforeCpu=cpu();
 const bytes=await render(cases[name]);
 if(!(bytes instanceof Uint8Array)||bytes.length<10000||new TextDecoder().decode(bytes.slice(0,5))!=='%PDF-')throw Error('actual_pdf_required');
 await Deno.writeFile(new URL(`./build/out/deno-${name}.pdf`,import.meta.url),bytes);
 results.push({name,pdf_bytes:bytes.length,wall_ms:performance.now()-before,cpu:elapsed(beforeCpu,cpu()),memory:Deno.memoryUsage()});
}
console.log(JSON.stringify({runtime:Deno.version,boot,results,total_wall_ms:performance.now()-started}));
