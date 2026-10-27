import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,writeFile,rm,access} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {createBoundedQualificationParser} from './qualification_management_upload_bounded_parser.mjs';

const bytes=new Uint8Array([1,2,3,4,5,6,7,8]);
test('bounded parser accepts only exact successful response',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'sko-parser-test-'));const worker=join(dir,'worker.cjs');
 try {await writeFile(worker,"process.stdin.resume();process.stdin.on('end',()=>process.stdout.write('VALID\\n'));\n");
 const parse=createBoundedQualificationParser({workerPath:worker,timeoutMs:2000});assert.equal(await parse({bytes,mime:'application/pdf'}),true);assert.equal(await parse({bytes,mime:'application/x-invalid'}),false);
 await writeFile(worker,"process.stdin.resume();process.stdin.on('end',()=>process.stdout.write('VALID\\nextra'));\n");assert.equal(await parse({bytes,mime:'application/pdf'}),false);
 await writeFile(worker,"process.stdin.resume();process.stdin.on('end',()=>{process.stdout.write('VALID\\n');process.exitCode=1});\n");assert.equal(await parse({bytes,mime:'application/pdf'}),false);
 }finally{await rm(dir,{recursive:true,force:true});}
});
test('parser deadline and oversized output fail closed',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'sko-parser-test-'));const worker=join(dir,'worker.cjs');
 try{await writeFile(worker,'process.stdin.resume();setInterval(()=>{},1000);');const parse=createBoundedQualificationParser({workerPath:worker,timeoutMs:150});assert.equal(await parse({bytes,mime:'application/pdf'}),false);
 await writeFile(worker,"process.stdout.write('X'.repeat(1000));setInterval(()=>{},1000)");assert.equal(await parse({bytes,mime:'application/pdf'}),false);
 }finally{await rm(dir,{recursive:true,force:true});}
});
test('configuration refuses unsafe inputs',()=>{assert.throws(()=>createBoundedQualificationParser({workerPath:'relative'}));assert.throws(()=>createBoundedQualificationParser({workerPath:'/tmp/x',timeoutMs:0}));});

test('spawn failure releases the slot after the child closes',async()=>{
 const parse=createBoundedQualificationParser({workerPath:'/not-present/worker.cjs',executable:'/not-present/node',timeoutMs:1000,maxConcurrent:1});
 assert.equal(await parse({bytes,mime:'application/pdf'}),false);
 assert.equal(await parse({bytes,mime:'application/pdf'}),false);
});

test('concurrent work is bounded and capacity is released after timeout',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'sko-parser-test-')); const worker=join(dir,'worker.cjs');
 try {
  await writeFile(worker,'process.stdin.resume();setInterval(()=>{},1000);');
  const parse=createBoundedQualificationParser({workerPath:worker,timeoutMs:500,maxConcurrent:1});
  const first=parse({bytes,mime:'application/pdf'});
  await assert.rejects(parse({bytes,mime:'application/pdf'}),/parser_busy/);
  assert.equal(await first,false);
  await writeFile(worker,"process.stdin.resume();process.stdin.on('end',()=>process.stdout.write('VALID\\n'));\n");
  assert.equal(await parse({bytes,mime:'application/pdf'}),true);
 } finally {await rm(dir,{recursive:true,force:true});}
});

test('deadline terminates a worker and its inherited process group', {skip:process.platform==='win32'}, async()=>{
 const dir=await mkdtemp(join(tmpdir(),'sko-parser-group-'));
 const worker=join(dir,'worker.cjs'),marker=join(dir,'unexpected-marker'),ready=join(dir,'child-started');
 try {
  const program=`const {spawn}=require('node:child_process');\n`+
    `spawn(process.execPath,['-e',${JSON.stringify(`const fs=require('node:fs');fs.writeFileSync(${JSON.stringify(ready)},'ready');setTimeout(()=>fs.writeFileSync(${JSON.stringify(marker)},'unexpected'),1500)`) }],{stdio:'ignore'});\n`+
    `process.stdin.resume();setInterval(()=>{},1000);\n`;
  await writeFile(worker,program);
  const parse=createBoundedQualificationParser({workerPath:worker,timeoutMs:1000,maxConcurrent:1});
  assert.equal(await parse({bytes,mime:'application/pdf'}),false);
  await access(ready);
  await new Promise(resolve=>setTimeout(resolve,1700));
  await assert.rejects(access(marker),{code:'ENOENT'});
 } finally {await rm(dir,{recursive:true,force:true});}
});
