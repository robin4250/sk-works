// New no-op/omission regressions only; reuse existing synthetic authorization bootstrap.
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {tmpdir} from 'node:os';
import {resolve,join,dirname} from 'node:path';
import {spawnSync} from 'node:child_process';
const root=process.cwd(),fixture=join(root,'tool/security/personnel_write/verify.mjs');
let source=await readFile(fixture,'utf8');
if(createHash('sha256').update(source).digest('hex')!=='ca2b9dce79a4f54ae6066d9aeae4b41b63f8342fde6e1b64a05ad8229e54d426')throw Error('Personnel bootstrap drift');
source=source.split('const baseline=await capsule();')[0];
source=source.replace("const here=path.dirname(fileURLToPath(import.meta.url));",'const here='+JSON.stringify(dirname(fixture))+';');
const folder=await mkdtemp(join(tmpdir(),'sko-birthday-noop-'));
const tail=String.raw`
await db.exec(fs.readFileSync(path.join(root,'supabase/migrations/20261016120458_personnel_write_permission_guard.sql'),'utf8'));
await db.exec("update worker_family_members set relation='child',birth_date='2020-01-01'");
await db.exec(fs.readFileSync(path.join(root,'tool/staged/employee_personnel_birth_date.sql.review-only'),'utf8'));
const patchFile=path.join(root,'tool/staged/personnel_birthday_noop.sql.review-only');
const beforeNoop=await capsule();
if(fs.existsSync(patchFile))await db.exec(fs.readFileSync(patchFile,'utf8'));
let checks=0;
const equal=(a,b,label)=>{assert.deepEqual(a,b,label);checks++;};
async function current(){await db.exec('reset role');return (await db.query('select private.worker_personnel_payload($1) value',[W])).rows[0].value;}
async function clientPayload(){const value=await current();delete value.birth_date_contract_version;return value;}
async function save(key,payload,target=W){await actor(actors[key]);return (await db.query('select public.save_worker_personnel_profile($1,$2::jsonb) value',[target,JSON.stringify(payload)])).rows[0].value;}
if(fs.existsSync(patchFile)){
 const afterNoop=await capsule();
 equal(afterNoop.rows,beforeNoop.rows,'candidate changes no business/protected rows');
 equal(afterNoop.policies,beforeNoop.policies,'candidate keeps every policy');
 equal(afterNoop.acl,beforeNoop.acl,'candidate keeps grants and table metadata');
 const metadata=functions=>functions.map(value=>value.proname==='save_worker_personnel_profile'?{...value,definition:null}:value);
 equal(metadata(afterNoop.functions),metadata(beforeNoop.functions),'only fourth-function body changes, attributes preserved');
}
await db.exec('begin');
let value=await clientPayload();value.birth_date='1980-02-29';await save('owner',value);
const baseline=await current();const same=await clientPayload();
// RED on the original1519 composition: marker makes a legitimate no-op become saved.
equal((await save('owner',same)).status,'unchanged','unchanged birthday with omitted contract marker');
const alteredMarker={...same,birth_date_contract_version:999};
equal((await save('owner',alteredMarker)).status,'unchanged','contract marker is not personnel data');
const omitted={...same};delete omitted.birth_date;
equal((await save('self',omitted)).status,'unchanged','old client date omission is a no-op');
const proposal={...omitted,address:'synthetic proposed address'};
const pending=await save('self',proposal);equal(pending.status,'pending','other field still requires configured approval');
await db.exec('reset role');
const request=(await db.query('select id,proposed,status from worker_personnel_change_requests where worker_id=$1 and status=$2',[W,'pending'])).rows[0];
equal(Object.hasOwn(request.proposed,'birth_date'),false,'stored proposal keeps date omission');
equal(request.proposed.address,'synthetic proposed address','other profile difference retained');
equal((await save('self',omitted)).status,'unchanged','no-op does not replace existing pending request');
await db.exec('reset role');
equal((await db.query('select id,proposed,status from worker_personnel_change_requests where id=$1',[request.id])).rows[0],request,'existing pending approval preserved');
// Simulate a separately authorized approved date change without rewriting the pending proposal.
const newer={...(await current()),birth_date:'1990-01-01'};
await db.query('select private.apply_worker_personnel_payload($1,$2::jsonb,$3)',[W,JSON.stringify(newer),actors.owner]);
await actor(actors.owner);await db.query('select public.decide_worker_personnel_change($1,true)',[request.id]);
value=await current();equal(value.birth_date,'1990-01-01','omitted proposal preserves approved date at application time');
equal(value.address,'synthetic proposed address','existing two-actor approval applies other field');
const clear=await clientPayload();clear.birth_date=null;
equal((await save('owner',clear)).status,'saved','explicit null clears supported date');
equal((await current()).birth_date,null,'explicit clear stored');
const empty=await clientPayload();empty.birth_date='';
equal((await save('owner',empty)).status,'unchanged','existing empty-string clear contract normalizes to null');
await db.exec('rollback;reset role');
for(const invalid of ['1980-02-31','2999-01-01','1899-12-31']){
 await db.exec('begin');const before=await capsule(),bad=await clientPayload();bad.birth_date=invalid;
 await assert.rejects(save('owner',bad));checks++;
 await db.exec('rollback;reset role');equal(await capsule(),before,'invalid date leaves no pending/request/data change');
}
for(const key of ['viewer','managerOff','outsider','deleted']){
 await db.exec('begin');const data=await clientPayload();await assert.rejects(save(key,data));checks++;
 await db.exec('rollback;reset role');
}
await db.exec('begin');const data=await clientPayload();await assert.rejects(save('owner',data,WF));checks++;
await db.exec('rollback;reset role');
if(fs.existsSync(patchFile)){
 const stored=await clientPayload();stored.birth_date='1980-02-29';await save('owner',stored);await db.exec('reset role');
 const beforeRestore=await capsule();
 await db.exec(fs.readFileSync(path.join(root,'tool/staged/personnel_birthday_noop_restore_unused.sql.review-only'),'utf8'));
 const restored=await capsule();
 equal(restored.rows,beforeRestore.rows,'unused recovery retains all dates/proposals/rows');
 equal(restored.functions,beforeNoop.functions,'unused recovery restores exact original routine metadata');
}
console.log('PASS '+checks+' new employee birthday no-op/marker/omission/clear/approval/invalid/authorization checks (synthetic PG17 claims)');
await db.close();
`;
try{
 await writeFile(join(folder,'check.mjs'),source+tail);
 const r=spawnSync(process.execPath,[join(folder,'check.mjs'),resolve(process.argv[2])],{stdio:'inherit',cwd:root,env:process.env});
 if(r.status!==0)process.exitCode=r.status??1;
}finally{await rm(folder,{recursive:true,force:true});}
