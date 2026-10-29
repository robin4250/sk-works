// Adapt only the saved synthetic Auth facade to real local GoTrue identities.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
export async function setupRealPersonnelFoundation({db,actors}){
 const fixture=path.join(process.cwd(),'tool/security/personnel_write/verify.mjs');
 let source=await fs.readFile(fixture,'utf8');
 assert.equal(createHash('sha256').update(source).digest('hex'),'ca2b9dce79a4f54ae6066d9aeae4b41b63f8342fde6e1b64a05ad8229e54d426');
 const cutoff='async function capsule(){';assert.equal(source.split(cutoff).length,2);source=source.split(cutoff)[0];
 const imports=source.split('\n').filter(line=>line.startsWith('import ')).join('\n');
 source=source.split('\n').filter(line=>!line.startsWith('import ')).join('\n');
 const replace=(old,next='')=>{assert.equal(source.split(old).length,2,old.slice(0,100));source=source.replace(old,()=>next);};
 replace('const here=path.dirname(fileURLToPath(import.meta.url));','const here='+JSON.stringify(path.dirname(fixture))+';');
 replace("const {PGlite}=await import(pathToFileURL(path.resolve(process.argv[2])).href);\nconst db=new PGlite();",'const db=context.db;');
 replace("const actors={managerOff:id(11),managerOn:id(12),owner:id(13),admin:id(14),viewer:id(15),self:id(16),employee:id(17),outsider:id(18),deleted:id(19),retiredSelf:id(20)};",'const actors=context.actors;');
 replace('create role authenticated;create role anon;create role service_role;create schema auth;');
 replace("create function auth.uid() returns uuid language sql stable as $$select coalesce(nullif(current_setting('fixture.actor',true),''),nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'sub')::uuid$$;\n");
 replace('create table auth.users(id uuid primary key);\n');
 replace('create table auth.identities(id uuid primary key,user_id uuid,provider text,provider_id text);\n');
 replace("for(const [key,uid]of Object.entries(actors)){await db.query('insert into auth.users values($1)',[uid]);await db.query('insert into auth.identities values($1,$2,$3,$4)',[id(100+Number(uid.slice(-2))),uid,'synthetic-fixture-provider','synthetic-'+key]);}\n");
 replace("async function actor(uid){await db.exec('reset role');await db.query(\"select set_config('fixture.actor',$1,false)\",[uid??'']);await db.exec('set role authenticated');}\n");
 assert.ok(!/\b(?:create\s+(?:or\s+replace\s+)?function|create\s+table|insert\s+into|update|delete\s+from|truncate)\s+auth\./i.test(source));
 const adapter={
  exec:async sql=>{assert.ok(!/\b(?:create\s+(?:or\s+replace\s+)?function|create\s+table|alter\s+table|insert\s+into|update|delete\s+from|truncate)\s+auth\./i.test(sql));assert.ok(!/set_config\(['"](?:fixture\.actor|request\.jwt\.claims)/i.test(sql));return db.query(sql);},
  query:async(sql,args)=>{assert.ok(!/\b(?:insert\s+into|update|delete\s+from|truncate)\s+auth\./i.test(sql));assert.ok(!/set_config\(['"](?:fixture\.actor|request\.jwt\.claims)/i.test(sql));return db.query(sql,args);},
 };
 const directory=await fs.mkdtemp(path.join(os.tmpdir(),'personnel-real-foundation-'));
 try{
  const file=path.join(directory,'setup.mjs');
  await fs.writeFile(file,imports+'\nexport async function setup(context){\n'+source+'\nreturn {C,F,W,WF,WR};\n}\n',{mode:0o600});
  const result=await (await import(pathToFileURL(file).href)).setup({db:adapter,actors});
  await db.query(await fs.readFile('supabase/migrations/20261016120458_personnel_write_permission_guard.sql','utf8'));
  return result;
 }finally{await fs.rm(directory,{recursive:true,force:true});}
}
