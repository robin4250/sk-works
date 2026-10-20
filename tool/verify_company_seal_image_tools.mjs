import fs from 'node:fs';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {deflateSync} from 'node:zlib';
const {PGlite}=await import(process.argv[2]);
const db=new PGlite();
const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const company=id(1),owner=id(2),outsider=id(3);
function crc32(bytes){let c=0xffffffff;for(const b of bytes){c^=b;for(let k=0;k<8;k++)c=(c>>>1)^((c&1)?0xedb88320:0);}return (c^0xffffffff)>>>0;}
function chunk(type,data){const t=Buffer.from(type);const size=Buffer.alloc(4);size.writeUInt32BE(data.length);const crc=Buffer.alloc(4);crc.writeUInt32BE(crc32(Buffer.concat([t,data])));return Buffer.concat([size,t,data,crc]);}
function png(color){const h=Buffer.alloc(13);h.writeUInt32BE(32,0);h.writeUInt32BE(32,4);h[8]=8;h[9]=6;const raw=Buffer.alloc(32*(1+32*4));for(let y=0;y<32;y++)for(let x=0;x<32;x++){const n=y*129+1+x*4;raw[n]=color;raw[n+3]=x%2?255:0;}return Buffer.concat([Buffer.from('89504e470d0a1a0a','hex'),chunk('IHDR',h),chunk('IDAT',deflateSync(raw)),chunk('IEND',Buffer.alloc(0))]);}
const bytes=png(255),base64=bytes.toString('base64'),hash=createHash('sha256').update(bytes).digest('hex');
try{
 await db.exec(`create schema auth;create schema private;create role anon;create role authenticated;create role service_role;
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
 create function private.account_access_allowed() returns boolean language sql stable as $$select auth.uid() is not null$$;
 create function private.aoyagi_reisho_name_supported(text) returns boolean language sql as $$select true$$;
 create table companies(id uuid primary key,name text,company_seal_style text default 'legacy');
 create table company_members(company_id uuid,user_id uuid,role text);
 insert into companies(id,name) values('${company}','検証株式会社');insert into company_members values('${company}','${owner}','owner');set test.uid='${owner}';`);
 const old=fs.readFileSync('supabase/migrations/20261010160154_company_seal_png_designs.sql','utf8');
 await db.exec(old.slice(old.indexOf('create or replace function private.document_company_seal_snapshot')));
 const candidate=fs.readFileSync(process.argv[3],'utf8');
 console.log('snapshot baseline', (await db.query("select md5(prosrc) h from pg_proc where oid='private.document_company_seal_snapshot(jsonb,uuid,boolean)'::regprocedure")).rows[0].h);
 await db.exec(candidate);
 await db.exec(`create function private.require_master_optional_feature(text) returns void language plpgsql as $$begin if current_setting('test.seal_enabled',true) is distinct from 'on' then raise exception 'feature disabled' using errcode='42501'; end if; end$$; set test.seal_enabled='on';`);
 await db.exec(fs.readFileSync(process.argv[4],'utf8'));
 const settings=async()=> (await db.query(`select public.company_uploaded_seal_settings('${company}') v`)).rows[0].v;
 const save=async(rev,pngValue=base64,sha=hash,enabled=true)=>(await db.query(`select public.save_company_uploaded_seal($1,$2,$3,$4,$5,$6) v`,[company,'検証株式会社',rev,pngValue,sha,enabled])).rows[0].v;
 const register=async(pngValue=base64,sha=hash)=>(await db.query(`select public.register_company_seal_png_version($1,$2,$3,$4) v`,[company,'検証株式会社',pngValue,sha])).rows[0].v;
 const before=await settings();const first=await register();assert.equal(first.sha256,hash);assert.deepEqual(await settings(),before);
 assert.equal((await register()).version_id,first.version_id);
 assert.equal((await db.query(`select public.company_seal_png_versions($1,$2) v`,[company,'検証株式会社'])).rows[0].v.length,1);
 const read=await db.query(`select public.company_seal_png_version($1,$2,$3) v`,[company,'検証株式会社',first.version_id]);
 assert.equal(Buffer.from(read.rows[0].v.png_base64,'base64').toString('hex'),bytes.toString('hex'));
 const active=await save(0);assert.equal(active.version_id,first.version_id);
 const frozen=(await db.query(`select private.document_company_seal_snapshot(null,$1,true) v`,[company])).rows[0].v;
 const b=png(128),h=createHash('sha256').update(b).digest('hex');await register(b.toString('base64'),h);assert.deepEqual(await settings(),active);
 await assert.rejects(save(0),/settings changed/);await assert.rejects(register(base64,'0'.repeat(64)),/hash differs/);
 await db.exec(`set test.seal_enabled='off'`);await assert.rejects(register(),/feature disabled/);await assert.rejects(save(1),/feature disabled/);
 assert.deepEqual((await db.query(`select private.document_company_seal_snapshot($1,$2,false) v`,[frozen,company])).rows[0].v,frozen);
 await save(1,null,null,false);assert.equal((await settings()).enabled,false);
 await db.exec(`set test.seal_enabled='on';set test.uid='${outsider}'`);await assert.rejects(register(),/permission required/);
 await assert.rejects(db.query(`select public.company_seal_png_version($1,$2,$3)`,[company,'検証株式会社',first.version_id]),/permission required/);
 await db.exec(`set test.uid='${owner}'`);await assert.rejects(db.exec('delete from private.company_seal_png_versions'),/immutable/);
 console.log('PASS append register preserves selection; immutable/dedup/history/read/CAS/master OFF/auth/frozen snapshot. No native/HTTP verification.');
}finally{await db.close();}
