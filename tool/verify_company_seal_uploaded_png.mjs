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
 const candidate=fs.readFileSync(process.argv[3]||'docs/candidates/company_seal_uploaded_png_20261020.sql.review-only','utf8');
 console.log('snapshot baseline', (await db.query("select md5(prosrc) h from pg_proc where oid='private.document_company_seal_snapshot(jsonb,uuid,boolean)'::regprocedure")).rows[0].h);
 await db.exec(candidate);
 const settings=async()=> (await db.query(`select public.company_uploaded_seal_settings('${company}') v`)).rows[0].v;
 const save=async(rev,pngValue=base64,sha=hash,enabled=true)=>(await db.query(`select public.save_company_uploaded_seal($1,$2,$3,$4,$5,$6) v`,[company,'検証株式会社',rev,pngValue,sha,enabled])).rows[0].v;
 const snapshot=async(existing=null,isNew=true)=>(await db.query(`select private.document_company_seal_snapshot($1,$2,$3) v`,[existing,company,isNew])).rows[0].v;
 assert.equal((await settings()).enabled,false);const legacy=await snapshot();
 const first=await save(0);assert.equal(first.enabled,true);assert.equal(first.revision,1);
 const frozen=await snapshot();
 assert.deepEqual((await db.query(`select public.company_current_uploaded_seal('${company}') v`)).rows[0].v.snapshot,frozen.company_seal_snapshot);assert.equal(frozen.company_seal_snapshot.version,2);assert.equal(frozen.company_seal_snapshot.png_sha256,hash);
 assert.deepEqual(await snapshot(legacy,false),legacy);await assert.rejects(save(0),/settings changed/);
 const secondBytes=png(128),secondHash=createHash('sha256').update(secondBytes).digest('hex');
 await save(1,secondBytes.toString('base64'),secondHash);assert.deepEqual(await snapshot(frozen,false),frozen);
 assert.equal((await db.query('select count(*)::int n from private.company_seal_png_versions')).rows[0].n,2);
 await assert.rejects(db.exec('update private.company_seal_png_versions set created_at=now()'),/immutable/);
 await assert.rejects(save(2,base64,'0'.repeat(64)),/hash differs/);
 await assert.rejects(save(2,Buffer.alloc(57).toString('base64'),hash),/invalid PNG/);
 const huge=Buffer.from(bytes);huge.writeUInt32BE(9999,16);
 await assert.rejects(save(2,huge.toString('base64'),createHash('sha256').update(huge).digest('hex')),/32-2048/);
 await db.exec(`set test.uid='${outsider}'`);await assert.rejects(settings(),/permission required/);await assert.rejects(save(2),/permission required/);
 await assert.rejects(db.query(`select public.company_current_uploaded_seal('${company}')`),/preview permission required/);
 await db.exec(`set role authenticated`);await assert.rejects(db.query('select * from private.company_seal_png_versions'),/permission denied/);
 await db.exec(`reset role;set test.uid='${owner}'; update company_members set role='manager'`);
 assert.equal((await db.query(`select public.company_current_uploaded_seal('${company}') v`)).rows[0].v.snapshot.version,2);
 await assert.rejects(settings(),/permission required/);
 await db.exec(`update company_members set role='owner'`);
 await save(2,null,null,false);assert.deepEqual(await snapshot(),legacy);
 await db.exec(`update companies set name='変更会社' where id='${company}'`);await assert.rejects(save(3,null,null,true),/company name changed/);
 console.log('PASS PNG backend fixture: authorization, immutable versions, SHA/dimensions/magic, revision guards, old snapshots and OFF fallback. UI/codec/native/HTTP not tested.');
}finally{await db.close();}
