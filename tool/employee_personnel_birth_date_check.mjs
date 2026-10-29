// Reuse the existing personnel authorization fixture; synthetic PostgreSQL only.
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
const folder=await mkdtemp(join(tmpdir(),'sko-employee-birth-'));
const tail=String.raw`
await db.exec(fs.readFileSync(path.join(root,'supabase/migrations/20261016120458_personnel_write_permission_guard.sql'),'utf8'));
await db.exec("update worker_family_members set relation='child',birth_date='2020-01-01'");
const before=await capsule();
const sql=fs.readFileSync(path.join(root,'tool/staged/employee_personnel_birth_date.sql.review-only'),'utf8');
await db.exec(sql);
let checks=0;
const equal=(a,b,label)=>{assert.deepEqual(a,b,label);checks++;};
const initial=await capsule();
equal(initial.policies,before.policies,'no policy changes');
equal(initial.acl.filter(x=>!(x.relname==='worker_personnel_profiles'&&x.attname==='birth_date')),before.acl,'no existing table privilege changes');
for(const t of businessTables){
 const rows=initial.rows[t].map(row=>{const copy={...row};if(t==='worker_personnel_profiles')delete copy.birth_date;return copy;});
 equal(rows,before.rows[t],'existing business data '+t);
}
equal(initial.functions.filter(x=>!['worker_personnel_payload','apply_worker_personnel_payload','employee_personnel_view'].includes(x.proname)),before.functions.filter(x=>!['worker_personnel_payload','apply_worker_personnel_payload','employee_personnel_view'].includes(x.proname)),'other routine metadata unchanged');
for(const t of protectedTables)equal(initial.rows[t],before.rows[t],'protected table '+t);
async function value(){return (await db.query('select private.worker_personnel_payload($1) value',[W])).rows[0].value;}
async function save(key,birth,omit=false){
 const original=await value();await actor(actors[key]);
 return (await db.query('select public.save_worker_personnel_profile($1,$2::jsonb) value',
 [W,JSON.stringify({...original,...(omit?{}:{birth_date:birth})})])).rows[0].value;
}
// Real canonical RPC and configured approval path under PostgreSQL roles/claims.
await db.exec('begin');
equal((await save('owner','1980-02-29')).status,'saved','owner canonical direct save');
await db.exec('reset role');equal((await value()).birth_date,'1980-02-29','stored owner date');
equal((await value()).birth_date_contract_version,1,'payload contract');
const proposed=await save('self','1990-01-01');equal(proposed.status,'pending','self requires existing approval');
await db.exec('reset role');equal((await value()).birth_date,'1980-02-29','pending does not change approved date');
const request=(await db.query('select id from worker_personnel_change_requests where worker_id=$1 and status=$2',[W,'pending'])).rows[0].id;
await actor(actors.owner);await db.query('select public.decide_worker_personnel_change($1,true)',[request]);
await db.exec('reset role');equal((await value()).birth_date,'1990-01-01','approved proposal applied');
// Omission uses actual old-client payload, not the modern payload containing DOB.
const old=await value();delete old.birth_date;delete old.birth_date_contract_version;
await actor(actors.owner);await db.query('select public.save_worker_personnel_profile($1,$2::jsonb)',[W,JSON.stringify(old)]);
await db.exec('reset role');equal((await value()).birth_date,'1990-01-01','old client omission preserves date');
await actor(actors.viewer);
const view=(await db.query('select public.employee_personnel_view($1) value',[C])).rows[0].value;
equal(view.records.find(x=>x.id===W).birthDate,'1990-01-01','authorized scoped view');
await db.exec('rollback;reset role');
for(const key of ['viewer','managerOff','outsider','deleted']){
 await db.exec('begin');await assert.rejects(save(key,'1980-01-01'));checks++;
 await db.exec('rollback;reset role');
}
for(const birth of ['2999-01-01','1980-02-31','1899-12-31']){
 await db.exec('begin');await assert.rejects(save('owner',birth));checks++;
 await db.exec('rollback;reset role');
}
await db.exec('begin');await actor(actors.viewer);
await assert.rejects(db.query('select public.employee_personnel_view($1)',[F]));checks++;
await db.exec('rollback;reset role');
// Recovery restores reviewed helper bodies but never drops the new column/data.
await db.exec('begin');await save('owner','1980-01-01');await db.exec('reset role');
await db.exec('commit');
await db.exec(fs.readFileSync(path.join(root,'tool/staged/employee_personnel_birth_date_restore_unused.sql.review-only'),'utf8'));
equal((await db.query('select birth_date::text value from worker_personnel_profiles where worker_id=$1',[W])).rows[0].value,'1980-01-01','unused recovery preserves date');
const restored=await capsule();equal(restored.functions,before.functions,'original routine metadata restored');
console.log('PASS '+checks+' employee birthday PostgreSQL authorization/approval/storage/recovery checks (synthetic claims, not GoTrue)');
await db.close();
`;
try{
 await writeFile(join(folder,'check.mjs'),source+tail);
 const r=spawnSync(process.execPath,[join(folder,'check.mjs'),resolve(process.argv[2])],{stdio:'inherit',cwd:root,env:process.env});
 if(r.status!==0)process.exitCode=r.status??1;
}finally{await rm(folder,{recursive:true,force:true});}
