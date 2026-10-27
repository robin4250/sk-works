import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';
const {default: pg}=await import(process.env.SKO_PG_PATH);const pool=new pg.Pool({connectionString:process.env.DATABASE_URL,max:30});
const actor='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',sid='bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
try{
 await pool.query(`create role anon;create role authenticated;create role service_role;create schema auth;create schema apple_native_enrollment_private;
 create function auth.jwt() returns jsonb language sql as $$select jsonb_build_object('role',current_setting('request.role',true))$$;
 create function apple_native_enrollment_private.ready() returns boolean language sql as $$select true$$;
 create function apple_native_enrollment_private.context(a uuid,s uuid) returns jsonb language sql as $$select case when a='${actor}' and s='${sid}' then '{}'::jsonb else null end$$;`);
 await pool.query(await readFile(new URL('../shared_rate.sql.review-only',import.meta.url),'utf8'));
 await pool.query('update apple_enrollment_rate_private.rollout set enabled=true');
 const take=async()=>{const c=await pool.connect();try{await c.query("select set_config('request.role','service_role',false)");return (await c.query('select public.take_apple_enrollment_attempt($1,$2) as v',[actor,sid])).rows[0].v.allowed;}finally{c.release();}};
 const results=await Promise.all(Array.from({length:30},take));assert.equal(results.filter(Boolean).length,5);assert.equal(results.filter(x=>!x).length,25);
 const count=await pool.query('select attempts from apple_enrollment_rate_private.windows');assert.equal(count.rows[0].attempts,6);
 await pool.query("update apple_enrollment_rate_private.windows set window_started=clock_timestamp()-interval '16 minutes'");assert.equal(await take(),true);
 console.log('30 concurrent sessions: exactly 5 admitted; durable counter and expiry verified');
}finally{await pool.end();}
