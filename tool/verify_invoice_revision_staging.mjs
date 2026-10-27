import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { pathToFileURL } from 'node:url';
import path from 'node:path';
const runtime = process.argv[2] ?? '../apple-enrollment-sql-runtime/node_modules/@electric-sql/pglite/dist/index.js';
const sql = process.argv[3] ?? new URL('./revision.sql.review-only', import.meta.url);
const native = process.argv.includes('--native');
let db;
let NativeClient;
if (native) {
  const pg = await import(pathToFileURL(path.resolve(process.argv[4])).href);
  const Client = pg.Client ?? pg.default?.Client;
  NativeClient = Client;
  const client = new Client({ connectionString: process.env.DATABASE_URL });
  await client.connect();
  db = { exec: s => client.query(s), query: (s, p) => client.query(s, p), close: () => client.end() };
} else {
  const entry = path.resolve(path.dirname(new URL(import.meta.url).pathname), runtime);
  const { PGlite } = await import(pathToFileURL(entry).href);
  const { pgcrypto } = await import(pathToFileURL(path.join(path.dirname(entry), 'contrib/pgcrypto.js')).href);
  db = new PGlite({ extensions: { pgcrypto } });
}
await db.exec(`
 create role anon; create role authenticated; create role service_role; create schema auth; create schema private; create schema extensions;
 create extension pgcrypto with schema extensions;
 create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('test.actor',true),'')::uuid $$;
 create function private.require_reauthentication_session() returns uuid language sql stable as $$ select nullif(current_setting('test.sid',true),'')::uuid $$;
 create function private.account_access_allowed() returns boolean language sql stable as $$ select coalesce(nullif(current_setting('test.allowed',true),'')::boolean,false) $$;
 create table public.company_members(company_id uuid not null,user_id uuid not null,role text,primary key(company_id,user_id));
 create table public.member_feature_permissions(company_id uuid not null,user_id uuid not null,can_manage_invoices boolean not null,primary key(company_id,user_id));
 create function private.has_company_feature(c uuid,f text) returns boolean language sql stable as $$ select c=nullif(current_setting('test.company',true),'')::uuid and f='can_manage_invoices' and exists(select 1 from public.company_members m where m.company_id=c and m.user_id=auth.uid() and (m.role in ('owner','admin') or exists(select 1 from public.member_feature_permissions p where p.company_id=c and p.user_id=m.user_id and p.can_manage_invoices))) $$;
 insert into public.company_members values('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000003','owner');
 create table public.invoices(id uuid primary key,company_id uuid not null,invoice_seal_frozen boolean not null,snapshot jsonb not null,created_at timestamptz not null default '2026-10-25T12:00:00Z');
 insert into public.invoices(id,company_id,invoice_seal_frozen,snapshot) values('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002',true,'{"sites":[{"days":5}],"company_seal_snapshot":{"synthetic":true}}');
 select set_config('test.actor','00000000-0000-0000-0000-000000000003',false),set_config('test.sid','00000000-0000-0000-0000-000000000004',false),set_config('test.company','00000000-0000-0000-0000-000000000002',false),set_config('test.allowed','true',false);
`);
await db.exec(await readFile(sql,'utf8'));
const id='00000000-0000-0000-0000-000000000001', cmd='00000000-0000-0000-0000-000000000005', src='a'.repeat(64);
await db.exec("set timezone='UTC'");
const hash=(await db.query(`select encode(sha256(convert_to(to_jsonb(i)::text,'UTF8')),'hex') h from invoices i where id=$1`,[id])).rows[0].h;
const stage=(command=cmd,source=src,original=hash,reason='勤務実績の追加')=>db.query('select invoice_revision_candidate.stage($1,$2,$3,$4,$5) v',[id,command,source,original,reason]);
await assert.rejects(stage(),/revision_disabled/);
await db.exec('update invoice_revision_candidate.settings set enabled=true');
await assert.rejects(stage(cmd,src,null),/revision_request_invalid/);
await db.exec("select set_config('test.allowed','false',false)");
await assert.rejects(stage(),/revision_denied/);
await db.exec("select set_config('test.allowed','true',false);select set_config('test.sid','',false)");
await assert.rejects(stage(),/revision_request_invalid/);
await db.exec("select set_config('test.sid','00000000-0000-0000-0000-000000000004',false);select set_config('test.company','00000000-0000-0000-0000-000000000099',false)");
await assert.rejects(stage(),/revision_denied/);
await db.exec("select set_config('test.company','00000000-0000-0000-0000-000000000002',false)");
await db.exec('delete from public.company_members');
await assert.rejects(stage(),/revision_denied/);
await db.exec("insert into public.company_members values('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000003','owner')");
await assert.rejects(stage(cmd,src,'b'.repeat(64)),/revision_original_changed/);
await assert.rejects(stage(),/revision_preview_unavailable/);
await db.exec(`create schema invoice_correction_preview_private;
 create table invoice_correction_preview_private.fixture(value jsonb);
 create function invoice_correction_preview_private.preview(uuid) returns jsonb language sql as $$ select value from invoice_correction_preview_private.fixture $$;`);
const preview={original_invoice_id:id,source_fingerprint:src,original_invoice_fingerprint:hash,calculation_blocked:false,proposed_snapshot:{sites:[{days:6},{days:1}]},subtotal:1,tax:1,welfare:0,grand_total:2};
const setPreview=async p=>{await db.exec('delete from invoice_correction_preview_private.fixture');await db.query('insert into invoice_correction_preview_private.fixture values($1::jsonb)',[JSON.stringify(p)]);};
for(const bad of [{...preview,source_fingerprint:'b'.repeat(64)},{...preview,calculation_blocked:true},{...preview,proposed_snapshot:{company_seal_snapshot:{}}},{...preview,grand_total:null}]){await setPreview(bad);await assert.rejects(stage(),/revision_preview_invalid_or_changed/);}
await setPreview(preview);const original=(await db.query('select to_jsonb(i) j from invoices i where id=$1',[id])).rows[0].j;
await db.exec("set timezone='Asia/Tokyo'");
assert.equal((await stage()).rows[0].v.replayed,false);
await db.exec("set timezone='UTC'");
assert.equal((await stage()).rows[0].v.replayed,true);
const review=async()=> (await db.query('select invoice_revision_candidate.read_prepared($1) v',[cmd])).rows[0].v;
const shown=await review();assert.equal(shown.status,'review_only');assert.deepEqual(shown.proposed_snapshot,preview.proposed_snapshot);
assert.equal('original_record' in shown,false);assert.equal('actor_id' in shown,false);assert.equal('session_id' in shown,false);
await db.exec("select set_config('test.actor','00000000-0000-0000-0000-000000000099',false)");
await assert.rejects(review(),/revision_denied/);
await db.exec("select set_config('test.actor','00000000-0000-0000-0000-000000000003',false);select set_config('test.sid','',false)");
await assert.rejects(review(),/revision_denied/);
await db.exec("select set_config('test.sid','00000000-0000-0000-0000-000000000004',false)");
await setPreview({...preview,source_fingerprint:'b'.repeat(64)});await assert.rejects(review(),/revision_preview_changed/);await setPreview(preview);
await db.query("update invoices set snapshot=snapshot||'{\"changed\":true}'::jsonb where id=$1",[id]);
await assert.rejects(review(),/revision_original_changed/);
await db.query('update invoices set snapshot=$1::jsonb where id=$2',[JSON.stringify(original.snapshot),id]);
await db.exec('update invoice_revision_candidate.settings set enabled=false');await assert.rejects(review(),/revision_disabled/);await db.exec('update invoice_revision_candidate.settings set enabled=true');
assert.equal((await review()).status,'review_only');
await assert.rejects(stage(cmd,src,hash,'別の理由'),/revision_request_reuse_conflict/);
await assert.rejects(stage('00000000-0000-0000-0000-000000000006'),/revision_existing_proposal/);
assert.deepEqual((await db.query('select to_jsonb(i) j from invoices i where id=$1',[id])).rows[0].j,original);
assert.equal((await db.query('select count(*)::int n from invoices')).rows[0].n,1);
for(const role of ['anon','authenticated','service_role']) {
 const access=await db.query("select has_schema_privilege($1,'invoice_revision_candidate','USAGE') s,has_function_privilege($1,'invoice_revision_candidate.stage(uuid,uuid,text,text,text)','EXECUTE') f",[role]);
 assert.deepEqual(access.rows[0],{s:false,f:false});
 assert.equal((await db.query("select has_function_privilege($1,'invoice_revision_candidate.read_prepared(uuid)','EXECUTE') f",[role])).rows[0].f,false);
}
if (native) {
  const nextId='00000000-0000-0000-0000-000000000011';
  await db.query('insert into public.invoices(id,company_id,invoice_seal_frozen,snapshot,created_at) select $1,company_id,invoice_seal_frozen,snapshot,created_at from public.invoices where id=$2',[nextId,id]);
  const nextHash=(await db.query(`select encode(sha256(convert_to(to_jsonb(i)::text,'UTF8')),'hex') h from invoices i where id=$1`,[nextId])).rows[0].h;
  await setPreview({...preview,original_invoice_id:nextId,original_invoice_fingerprint:nextHash});
  const a=new NativeClient({connectionString:process.env.DATABASE_URL}),b=new NativeClient({connectionString:process.env.DATABASE_URL});
  await Promise.all([a.connect(),b.connect()]);
  const waitingPid=(await b.query('select pg_backend_pid() pid')).rows[0].pid;
  const waitForBlock=async()=>{
    for(let i=0;i<50;i++){
      if((await db.query('select cardinality(pg_blocking_pids($1))>0 blocked',[waitingPid])).rows[0].blocked)return;
      await new Promise(resolve=>setTimeout(resolve,30));
    }
    throw Error('expected transaction lock wait was not observed');
  };
  const setup=`select set_config('test.actor','00000000-0000-0000-0000-000000000003',false),set_config('test.sid','00000000-0000-0000-0000-000000000004',false),set_config('test.company','00000000-0000-0000-0000-000000000002',false),set_config('test.allowed','true',false)`;
  await Promise.all([a.query(setup),b.query(setup)]);
  const query='select invoice_revision_candidate.stage($1,$2,$3,$4,$5) v';
  const race=await Promise.allSettled([
    a.query(query,[nextId,'00000000-0000-0000-0000-000000000015',src,nextHash,'追加']),
    b.query(query,[nextId,'00000000-0000-0000-0000-000000000016',src,nextHash,'追加'])]);
  assert.equal(race.filter(r=>r.status==='fulfilled').length,1);
  assert.match(race.find(r=>r.status==='rejected').reason.message,/revision_existing_proposal/);
  assert.equal((await db.query('select count(*)::int n from invoice_revision_candidate.proposals where original_invoice_id=$1',[nextId])).rows[0].n,1);
  const thirdId='00000000-0000-0000-0000-000000000021';
  await db.query('insert into public.invoices(id,company_id,invoice_seal_frozen,snapshot,created_at) select $1,company_id,invoice_seal_frozen,snapshot,created_at from public.invoices where id=$2',[thirdId,id]);
  const thirdHash=(await db.query(`select encode(sha256(convert_to(to_jsonb(i)::text,'UTF8')),'hex') h from invoices i where id=$1`,[thirdId])).rows[0].h;
  await setPreview({...preview,original_invoice_id:thirdId,original_invoice_fingerprint:thirdHash});
  await a.query('begin');
  await a.query(query,[thirdId,'00000000-0000-0000-0000-000000000025',src,thirdHash,'追加']);
  let revoked=false;
  const revocation=b.query("update public.company_members set role='worker' where user_id='00000000-0000-0000-0000-000000000003'").then(()=>{revoked=true;});
  await waitForBlock();
  assert.equal(revoked,false,'role revocation must wait for proposal transaction');
  await a.query('commit');
  await revocation;
  await assert.rejects(a.query(query,[thirdId,'00000000-0000-0000-0000-000000000026',src,thirdHash,'追加']),/revision_denied/);
  await db.exec("update public.company_members set role='manager'; insert into public.member_feature_permissions values('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000003',true)");
  const fourthId='00000000-0000-0000-0000-000000000031';
  await db.query('insert into public.invoices(id,company_id,invoice_seal_frozen,snapshot,created_at) select $1,company_id,invoice_seal_frozen,snapshot,created_at from public.invoices where id=$2',[fourthId,id]);
  const fourthHash=(await db.query(`select encode(sha256(convert_to(to_jsonb(i)::text,'UTF8')),'hex') h from invoices i where id=$1`,[fourthId])).rows[0].h;
  await setPreview({...preview,original_invoice_id:fourthId,original_invoice_fingerprint:fourthHash});
  await a.query('begin');
  await a.query(query,[fourthId,'00000000-0000-0000-0000-000000000035',src,fourthHash,'追加']);
  let permissionRevoked=false;
  const revokePermission=b.query('update public.member_feature_permissions set can_manage_invoices=false').then(()=>{permissionRevoked=true;});
  await waitForBlock();
  assert.equal(permissionRevoked,false,'permission revocation must wait for proposal transaction');
  await a.query('commit');
  await revokePermission;
  await assert.rejects(a.query(query,[fourthId,'00000000-0000-0000-0000-000000000036',src,fourthHash,'追加']),/revision_denied/);
  await Promise.all([a.end(),b.end()]);
}
await db.query('delete from invoices where id=$1',[id]);
assert.deepEqual((await db.query('select original_record from invoice_revision_candidate.proposals where id=$1',[cmd])).rows[0].original_record,original);
console.log('PASS isolated revision staging: gate, identity, scope, stale source, seal refusal, immutable original, idempotency and no publication');
await db.close();
