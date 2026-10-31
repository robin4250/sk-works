// Internal request-scoped coordinator, not an Edge Function/public upload API.
// Caller owns a dedicated privileged DB connection with the original verified
// request claims already installed. Never use this on a shared connection pool
// without its existing per-request claim isolation.
import {spawn} from 'node:child_process';
import {realpath} from 'node:fs/promises';
import {isAbsolute,join} from 'node:path';

const maxPdf=20*1024*1024;
export async function createCanonicalSiteOrderRenderer({dartExecutable,repositoryRoot}) {
 if(!isAbsolute(dartExecutable)||!isAbsolute(repositoryRoot))throw Error('canonical_renderer_configuration');
 const dart=await realpath(dartExecutable),root=await realpath(repositoryRoot);
 const command=join(root,'tool/render_site_order_canonical.dart');
 const packages=join(root,'tool/canonical_renderer/.dart_tool/package_config.json');
 return evidence=>new Promise((resolve,reject)=>{
  const input=Buffer.from(JSON.stringify(evidence));
  if(input.length>2*1024*1024){reject(Error('canonical_evidence_too_large'));return;}
  const child=spawn(dart,[`--packages=${packages}`,command,root],{
   cwd:root,env:{LANG:'C.UTF-8'},stdio:['pipe','pipe','pipe']});
  let length=0,failed=false;const chunks=[];
  const fail=()=>{if(failed)return;failed=true;child.kill('SIGKILL');reject(Error('canonical_render_rejected'));};
  const timer=setTimeout(fail,30_000);
  child.on('error',fail);child.stdin.on('error',fail);
  // Diagnostics deliberately never forwarded: evidence can include private data.
  child.stderr.resume();
  child.stdout.on('data',part=>{length+=part.length;if(length>maxPdf){fail();return;}chunks.push(part);});
  child.on('close',code=>{
   clearTimeout(timer);if(failed)return;
   const bytes=Buffer.concat(chunks);
   if(code!==0||bytes.length<16||bytes.subarray(0,5).toString()!=='%PDF-') {fail();return;}
   resolve(bytes);
  });
  child.stdin.end(input);
 });
}

export {registerCanonicalSiteOrderJob,registerManagerCanonicalSiteOrderJob,processCanonicalSiteOrderReply} from './site_order_canonical_core.mjs';
