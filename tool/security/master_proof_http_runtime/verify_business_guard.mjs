import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const dir=fileURLToPath(new URL('.',import.meta.url));
const {PGlite}=await import(process.argv[2]);
const source=JSON.parse(execFileSync('python3',['-c',"import json;import owner_master_proof_http_rehearsal as h;print(json.dumps({'queries':h.BUSINESS_ROW_QUERIES_SQL,'prerequisites':h.COLLECTOR_PREREQUISITES_SQL}))"],{cwd:dir,encoding:'utf8'}));
const db=new PGlite();let checks=0;
try{
 await db.exec(`create schema private;create schema auth;create schema extensions;
 create table public.payroll_statements(id int primary key,net int);insert into public.payroll_statements values(1,100);
 create table public.expenses(id int primary key,amount int);insert into public.expenses values(1,1000);
 create table private.original_settings(id int primary key,enabled boolean);insert into private.original_settings values(1,false);
 create table private.master_admins(user_id int primary key,enabled boolean);insert into private.master_admins values(1,true);`);
 const queries=(await db.query(source.queries)).rows[0].coalesce;
 assert.equal(queries.length,3);checks++;
 const sql=execFileSync('python3',['-c',"import json,sys;import owner_master_proof_http_rehearsal as h;print(h.business_digest_sql(json.load(sys.stdin)))"],{cwd:dir,input:JSON.stringify(queries),encoding:'utf8'});
 const capture=async()=>JSON.stringify((await db.query(sql)).rows);
 const before=await capture();
 await db.exec('create table private.reauthentication_proofs(proof_hash text);insert into private.reauthentication_proofs values(\'new-test-data\');');
 assert.equal(await capture(),before);checks++;
 await db.exec('insert into private.master_admins values(2,true)');assert.equal(await capture(),before);checks++;
 await db.exec('begin;update public.payroll_statements set net=99 where id=1;');assert.notEqual(await capture(),before);checks++;await db.exec('rollback');
 await db.exec('begin;insert into public.expenses values(2,-1000);');assert.notEqual(await capture(),before);checks++;await db.exec('rollback');
 await db.exec('begin;update private.original_settings set enabled=true;');assert.notEqual(await capture(),before);checks++;await db.exec('rollback');
 assert.equal(await capture(),before);checks++;
 // Missing canonical prerequisite functions must stop before candidate install.
 assert.equal((await db.query(source.prerequisites)).rows[0]['?column?'],false);checks++;
 console.log(JSON.stringify({verified:true,checks,native_proof:false,scope:'actual generated SQL detects original business row mutations'}));
}finally{await db.close();}
