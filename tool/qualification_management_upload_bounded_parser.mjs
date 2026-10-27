import {spawn} from 'node:child_process';
import {isAbsolute} from 'node:path';

// Candidate only. The host must supply an externally sandboxed, pinned worker.
// The deadline covers process start, stdin transfer, parsing and exit. The worker
// receives no credentials; only file bytes and the declared MIME type.
export function createBoundedQualificationParser({workerPath, timeoutMs=5000, executable=process.execPath}) {
 if(typeof workerPath!=='string'||!isAbsolute(workerPath)||typeof executable!=='string'||!isAbsolute(executable)||!Number.isSafeInteger(timeoutMs)||timeoutMs<50||timeoutMs>30000) throw Error('parser_unavailable');
 return async function validateFile({bytes,mime}) {
  if(!(bytes instanceof Uint8Array)||bytes.length<8||bytes.length>20*1024*1024||!['image/jpeg','image/png','image/heic','application/pdf'].includes(mime))return false;
  return await new Promise(resolve=>{
   let child, timer, done=false, output=Buffer.alloc(0), overflow=false;
   const kill=()=>{if(!child?.pid)return; try{if(process.platform!=='win32')process.kill(-child.pid,'SIGKILL');else child.kill('SIGKILL');}catch{try{child.kill('SIGKILL');}catch{}}};
   const finish=value=>{if(done)return;done=true;clearTimeout(timer);kill();resolve(value);};
   try {
    child=spawn(executable,[workerPath,mime],{stdio:['pipe','pipe','ignore'],env:{},detached:process.platform!=='win32',windowsHide:true});
    timer=setTimeout(()=>finish(false),timeoutMs);
    child.on('error',()=>finish(false));
    child.stdout.on('error',()=>finish(false));
    child.stdin.on('error',()=>finish(false));
    child.stdout.on('data',chunk=>{if(done)return; if(output.length+chunk.length>64){overflow=true;finish(false);return;} output=Buffer.concat([output,chunk]);});
    child.on('close',(code,signal)=>finish(!overflow&&code===0&&signal===null&&output.toString('utf8')==='VALID\n'));
    child.stdin.end(Buffer.from(bytes));
   } catch { finish(false); }
  });
 };
}
