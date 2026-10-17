import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import { createHmac } from 'node:crypto';

const actualPg = process.argv.includes('--postgres');
for(const name of ['SUPABASE_URL','SUPABASE_ACCESS_TOKEN','SUPABASE_SERVICE_ROLE_KEY',
  'SUPABASE_DB_PASSWORD','SUPABASE_PROJECT_ID'])assert.ok(!process.env[name], 'Hosted credentials are forbidden');
let db;
if(actualPg){
  const u=new URL(process.env.SKO_R19_DB_URL||'');
  assert.equal(u.hostname,'127.0.0.1');assert.equal(u.pathname,'/sko_r19_fixture');
  const {default:pg}=await import(pathToFileURL(process.argv[2]).href);
  const client=new pg.Client({connectionString:u.href});await client.connect();
  db={exec:s=>client.query(s),query:(s,v)=>client.query(s,v),close:()=>client.end()};
}else{
  const {PGlite}=await import(pathToFileURL(process.argv[2]).href);db=new PGlite();
}
const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const kinds=['invoices','communication_groups','communication_notes','communication_albums',
  'communication_album_items','attendance_correction_requests','attendance_correction_items','app_notifications'];
let count=0;
try{
  assert.equal((await db.query("select count(*)::int n from pg_tables where schemaname='public'")).rows[0].n,0);
  await db.exec(`create role anon;create role authenticated;create role authenticator login password 'fixture-only' noinherit;
    grant anon,authenticated to authenticator;create schema private;create schema auth;create schema storage;
  `);
}catch(error){
  // UUID return casts are explicit rather than relying on implicit text coercion.
  await db.close();throw error;
}
try{
  await db.exec(`create or replace function auth.uid() returns uuid language sql stable as $$select (nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'sub')::uuid$$;
    create table private.master_admins(user_id uuid primary key,enabled boolean);
    create table private.line_history_analysis_groups(group_id uuid,company_id uuid);
    create table private.line_invoice_submissions(invoice_id uuid,company_id uuid);
    create table private.line_historical_invoice_links(invoice_id uuid,company_id uuid);
    create table private.line_attendance_submissions(request_id uuid,company_id uuid);
    create table private.r19_members(user_id uuid,company_id uuid);
    create function private.account_access_allowed() returns boolean language sql stable as $$select auth.uid() is not null$$;
    create function private.try_uuid(p text) returns uuid language plpgsql immutable as $$begin return p::uuid;exception when invalid_text_representation then return null;end$$;
    create function private.r19_scope(c uuid) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from private.r19_members where user_id=auth.uid() and company_id=c)$$;
    grant usage on schema private,auth,storage to authenticated;
    grant execute on function private.r19_scope(uuid),auth.uid() to authenticated;
    insert into private.master_admins values('${id(1)}',true),('${id(4)}',false),('${id(5)}',true);
    insert into private.r19_members values('${id(1)}','${id(10)}'),('${id(2)}','${id(10)}'),('${id(4)}','${id(10)}'),('${id(5)}','${id(11)}');
  `);
  for(const table of kinds){
    await db.exec(`create table public.${table}(id uuid primary key,company_id uuid,group_id uuid,request_id uuid,action_key text,action_id uuid,body text);
      alter table public.${table} enable row level security;
      grant select on public.${table} to authenticated;
      create policy ordinary_scope on public.${table} for select to authenticated using(private.r19_scope(company_id));
      insert into public.${table} values('${id(20)}','${id(10)}','${id(30)}','${id(20)}','invoice_approval','${id(20)}','ordinary'),
      ('${id(21)}','${id(10)}','${id(31)}','${id(21)}','invoice_approval','${id(21)}','linked'),
      ('${id(22)}','${id(11)}','${id(32)}','${id(22)}','invoice_approval','${id(22)}','foreign');`);
  }
  // Group ids are referenced directly in the group table; align fixture ids.
  await db.exec(`update public.communication_groups set id='${id(31)}' where id='${id(21)}';
    insert into private.line_history_analysis_groups values('${id(31)}','${id(10)}');
    insert into private.line_invoice_submissions values('${id(21)}','${id(10)}');
    insert into private.line_attendance_submissions values('${id(21)}','${id(10)}');
    create table storage.objects(id uuid primary key,company_id uuid,bucket_id text,name text);
    alter table storage.objects enable row level security;grant select on storage.objects to authenticated;
    create policy ordinary_scope on storage.objects for select to authenticated using(private.r19_scope(company_id));
    insert into storage.objects values('${id(20)}','${id(10)}','communication-notes','${id(10)}/${id(30)}/photo.png'),
    ('${id(21)}','${id(10)}','communication-albums','${id(10)}/${id(31)}/photo.png'),
    ('${id(22)}','${id(10)}','worker-documents','unrelated.png');`);
  const tables=[...kinds.map(t=>`public.${t}`),'storage.objects'];
  const before=await Promise.all(tables.map(t=>db.query(`select * from ${t} order by id`)));
  const policySnapshot=async()=> (await db.query("select schemaname,tablename,policyname,permissive,roles::text,cmd,qual,with_check from pg_policies order by schemaname,tablename,policyname")).rows;
  const policiesBefore=await policySnapshot();
  const read=async(table,actor)=>{
    await db.exec('set role authenticated');
    try{await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:actor})]);
      return (await db.query(`select id from ${table} order by id`)).rows;
    }finally{await db.exec('reset role');}
  };
  assert.equal((await read('public.invoices',id(2))).length,2);count++;
  await db.exec(await fs.readFile(new URL('./r19_candidate.sql.review-only',import.meta.url),'utf8'));
  const helpers=(await db.query(`select p.proname,p.prosecdef,p.proconfig::text,
    pg_get_userbyid(p.proowner) owner,
    has_function_privilege('anon',p.oid,'EXECUTE') anon_exec,
    has_function_privilege('authenticated',p.oid,'EXECUTE') auth_exec
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='private' and p.proname in
    ('r19_master','r19_group_allowed','r19_invoice_allowed','r19_request_allowed','r19_notice_allowed','r19_file_allowed')
    order by p.proname`)).rows;
  assert.equal(helpers.length,6);count++;
  for(const helper of helpers){
    assert.equal(helper.prosecdef,true);assert.equal(helper.anon_exec,false);
    assert.equal(helper.auth_exec,true);assert.equal(helper.owner,'postgres');
    assert.match(helper.proconfig,/search_path=/);count++;
  }
  await db.exec('set role authenticated');
  try{await assert.rejects(db.query('select * from private.line_invoice_submissions'));count++;}
  finally{await db.exec('reset role');}
  for(const actor of [id(2),id(4)])for(const table of tables){
    const rows=await read(table,actor);assert.ok(!rows.some(r=>[id(21),id(31)].includes(r.id)));count++;
    assert.ok(rows.some(r=>r.id===id(20)));count++;
  }
  for(const table of tables){assert.ok((await read(table,id(1))).some(r=>[id(21),id(31)].includes(r.id)));count++;
    assert.ok(!(await read(table,id(5))).some(r=>[id(21),id(31)].includes(r.id)));count++;}
  if(actualPg){
    const origin=new URL(process.env.SKO_R19_REST_URL||'');assert.equal(origin.origin,'http://127.0.0.1:3099');
    const key='r19-isolated-fixture-signing-key-20261017';
    const token=actor=>{const b=v=>Buffer.from(JSON.stringify(v)).toString('base64url');
      const s=b({alg:'HS256',typ:'JWT'})+'.'+b({role:'authenticated',sub:actor,exp:Math.floor(Date.now()/1000)+300});
      return s+'.'+createHmac('sha256',key).update(s).digest('base64url');};
    await db.exec("notify pgrst, 'reload schema'");
    let ready=false;
    for(let attempt=0;attempt<30;attempt++){
      try{const probe=await fetch(new URL('/invoices?select=id',origin),
        {headers:{Authorization:'Bearer '+token(id(1))},redirect:'error'});
        if(probe.status===200){ready=true;break;}
      }catch{/* Only the disposable service may be starting. */}
      await new Promise(resolve=>setTimeout(resolve,1000));
    }
    assert.ok(ready,'Local PostgREST schema did not become ready');
    for(const actor of [id(1),id(2),id(4),id(5)])for(const table of tables){
      const [schema,name]=table.split('.');const url=new URL('/'+name+'?select=id',origin);
      const response=await fetch(url,{headers:{Authorization:'Bearer '+token(actor),'Accept-Profile':schema},redirect:'error'});
      assert.equal(response.status,200);const rows=await response.json();
      const visible=rows.some(r=>[id(21),id(31)].includes(r.id));
      assert.equal(visible,actor===id(1));count++;
    }
    const anonymous=await fetch(new URL('/invoices',origin),{redirect:'error'});assert.ok([401,403].includes(anonymous.status));count++;
    console.log('VERIFIED actual PG17/PostgREST signed synthetic JWT SELECT boundary; not GoTrue issuance or real Storage HTTP.');
  }
  for(let i=0;i<tables.length;i++){
    assert.deepEqual((await db.query(`select * from ${tables[i]} order by id`)).rows,before[i].rows);count++;
    await db.exec(`drop policy r19_boundary on ${tables[i]}`);
  }
  assert.deepEqual(await policySnapshot(),policiesBefore);count++;
  assert.equal((await read('public.invoices',id(2))).length,2);count++;
  console.log(`PASS ${count} checks; linked rows restricted, ordinary rows and all data preserved, original-policy behavior restored. Incomplete provenance, definer RPC, push, real Storage and final attendance remain blockers.`);
}finally{await db.close();}
