import assert from 'node:assert/strict';
import { pathToFileURL } from 'node:url';

// Design exercise only: new in-memory database, no network client or credentials.
const modulePath = process.argv[2];
if (!modulePath) throw new Error('Pass the pinned repository-local PGlite module');
const { PGlite } = await import(pathToFileURL(modulePath).href);
const db = new PGlite();
let assertions = 0;
try {
  await db.exec(`
    create role authenticated;
    create schema private;
    create table private.actors(id text primary key, company_id text, is_master boolean);
    create table private.r17_links(kind text, object_id text, company_id text,
      state text check(state in ('protected','unresolved')), primary key(kind,object_id));
    create table public.r17_fixture(kind text, id text, company_id text, body text,
      primary key(kind,id));
    insert into private.actors values ('master','a',true),('admin','a',false),
      ('worker','a',false),('foreign','b',false),('disabled','a',false);
    create function private.actor() returns text language sql stable
      as $$select current_setting('r17.actor',true)$$;
    create function private.same_company(c text) returns boolean language sql stable security definer
      set search_path='' as $$select exists(select 1 from private.actors
      where id=private.actor() and company_id=c)$$;
    create function private.r17_visible(k text,i text,c text) returns boolean
      language sql stable security definer set search_path='' as $$
      select not exists(select 1 from private.r17_links where kind=k and object_id=i)
      or (exists(select 1 from private.actors where id=private.actor() and is_master)
        and exists(select 1 from private.r17_links where kind=k and object_id=i
          and company_id=c and state='protected'))$$;
    revoke all on all tables in schema private from public;
    revoke all on function private.r17_visible(text,text,text) from public;
    grant usage on schema private to authenticated;
    grant execute on function private.actor(),private.same_company(text),
      private.r17_visible(text,text,text) to authenticated;
    alter table public.r17_fixture enable row level security;
    grant select on public.r17_fixture to authenticated;
    create policy existing_scope on public.r17_fixture for select to authenticated
      using(private.same_company(company_id));
  `);
  const kinds = ['invoice','attendance_request','attendance_item','attendance',
    'analysis_group','note','album','photo','notification','search_result'];
  for (const kind of kinds) {
    await db.query(`insert into public.r17_fixture values ($1,'ordinary','a','ordinary'),
      ($1,'linked','a','private content'),($1,'unresolved','a','unclassified'),
      ($1,'inconsistent','a','wrong company linkage'),($1,'other','b','other company')`, [kind]);
    await db.query(`insert into private.r17_links values ($1,'linked','a','protected'),
      ($1,'unresolved','a','unresolved'),($1,'inconsistent','b','protected'),
      ($1,'other','b','protected')`, [kind]);
  }
  const read = async (actor) => {
    await db.exec(`set role authenticated;`);
    try {
      await db.query(`select set_config('r17.actor',$1,false)`,[actor]);
      return (await db.query(`select kind,id from public.r17_fixture order by kind,id`)).rows;
    } finally { await db.exec('reset role'); }
  };
  // Reproduce the generic company-policy gap before the proposed extra boundary.
  assert.equal((await read('admin')).length, kinds.length * 4); assertions++;
  const before = await db.query('select * from public.r17_fixture order by kind,id');
  await db.exec(`create policy r17_scoped_boundary on public.r17_fixture as restrictive
    for select to authenticated using(private.r17_visible(kind,id,company_id));`);
  for(const actor of ['admin','worker','disabled']) {
    const rows=await read(actor);
    assert.equal(rows.length,kinds.length); assertions++;
    assert.ok(rows.every(r=>r.id==='ordinary')); assertions++;
  }
  const master=await read('master');
  assert.equal(master.length,kinds.length*2); assertions++;
  assert.ok(master.every(r=>['ordinary','linked'].includes(r.id))); assertions++;
  assert.equal((await read('foreign')).length,0); assertions++;
  assert.equal((await read('')).length,0); assertions++;
  assert.deepEqual(await db.query('select * from public.r17_fixture order by kind,id'),before); assertions++;
  await db.exec('drop policy r17_scoped_boundary on public.r17_fixture');
  assert.equal((await read('admin')).length,kinds.length*4); assertions++;
  console.log(`PASS ${assertions} synthetic SQL boundary checks across ${kinds.length} kinds; ordinary rows/contents and original policy restored. NOT deployed RLS, real REST/RPC/Storage/Realtime or complete lineage proof.`);
} finally { await db.close(); }
