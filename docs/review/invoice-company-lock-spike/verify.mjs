// Synthetic isolation experiment. Never use against an application database.
import assert from 'node:assert/strict';
import pg from 'pg';
const url = new URL(process.env.FIXTURE_URL || 'http://invalid');
if (process.env.CI !== 'true' || url.protocol !== 'postgresql:' ||
    url.hostname !== '127.0.0.1' || url.port !== '5432' ||
    url.pathname !== '/sko_lock_fixture' ||
    Object.keys(process.env).some(k => /^SUPABASE_(ACCESS_TOKEN|DB_PASSWORD|URL|SERVICE_ROLE_KEY|SECRET_KEY|PROJECT_REF)$/.test(k)))
  throw Error('isolated CI fixture only');
const clients = Array.from({length: 4}, () => new pg.Client({connectionString:url.toString()}));
const [setup, approval, same, other] = clients;
const sql = "select pg_advisory_xact_lock(hashtextextended($1::text, 319847))";
try {
  await Promise.all(clients.map(c => c.connect()));
  const exists = await setup.query("select to_regclass('public.synthetic_work') as t");
  assert.equal(exists.rows[0].t, null);
  await setup.query("create table public.synthetic_work(company_id uuid not null, v text not null)");
  const a = '10000000-0000-0000-0000-000000000001';
  const b = '10000000-0000-0000-0000-000000000002';

  // Writer obtains the same company lock BEFORE any write. Other company can
  // write immediately, same company times out; no production trigger exists.
  await approval.query('begin');
  await approval.query(sql,[a]);
  await other.query('begin');
  await other.query("set local lock_timeout='750ms'");
  await other.query(sql,[b]);
  await other.query('insert into public.synthetic_work values($1,$2)',[b,'other company']);
  await other.query('commit');
  await same.query('begin');
  await same.query("set local lock_timeout='300ms'");
  await assert.rejects(() => same.query(sql,[a]), e => e.code === '55P03');
  await same.query('rollback');
  await approval.query('rollback');

  // Lock waits until a cooperating pending writer commits; a READ COMMITTED
  // query executed after acquisition observes its insertion.
  await same.query('begin');
  await same.query(sql,[a]);
  await same.query('insert into public.synthetic_work values($1,$2)',[a,'prior writer']);
  await approval.query('begin');
  const acquired=approval.query(sql,[a]);
  await same.query('commit');
  await acquired;
  const current=await approval.query('select count(*)::int as n from public.synthetic_work where company_id=$1',[a]);
  assert.equal(current.rows[0].n,1);
  await approval.query('rollback');

  // An unmodified direct write ignores advisory locks entirely: this is an
  // explicit release blocker, not evidence that the design is deployable.
  await approval.query('begin');
  await approval.query(sql,[a]);
  await same.query('begin');
  await same.query("set local lock_timeout='750ms'");
  await same.query('insert into public.synthetic_work values($1,$2)',[a,'bypass']);
  await same.query('commit');
  const bypass=await approval.query("select count(*)::int as n from public.synthetic_work where company_id=$1 and v='bypass'",[a]);
  assert.equal(bypass.rows[0].n,1);
  await approval.query('rollback');
  // A row trigger that takes the company advisory lock may be too late:
  // UPDATE owns the tuple before BEFORE ROW executes. The approver owns the
  // advisory lock first and then tries to update the same tuple. This is a
  // negative control, not a proposed production trigger.
  await setup.query(`create function public.synthetic_row_guard() returns trigger
    language plpgsql as $body$ begin
    perform pg_advisory_xact_lock(hashtextextended(NEW.company_id::text,319847));
    return NEW; end $body$`
);
  await setup.query('create trigger synthetic_guard before update on public.synthetic_work for each row execute function public.synthetic_row_guard()');
  const writerPid=(await same.query('select pg_backend_pid() as pid')).rows[0].pid;
  await approval.query('begin');
  await approval.query("set local statement_timeout='5s'");
  await approval.query("set local deadlock_timeout='100ms'");
  await approval.query(sql,[a]);
  await same.query('begin');
  await same.query("set local statement_timeout='5s'");
  await same.query("set local deadlock_timeout='100ms'");
  const writer= same.query("update public.synthetic_work set v='writer' where company_id=$1 and v='prior writer'",[a]).then(()=>null,e=>e);
  let blocked=false;
  for (let i=0;i<40;i++) {
    const blockers=(await setup.query('select pg_blocking_pids($1) as pids',[writerPid])).rows[0].pids;
    if (blockers.length) {blocked=true;break;}
    await new Promise(resolve=>setTimeout(resolve,25));
  }
  assert.equal(blocked,true,'writer never waited on advisory lock');
  const approver=approval.query("update public.synthetic_work set v='approver' where company_id=$1 and v='prior writer'",[a]).then(()=>null,e=>e);
  const errors=await Promise.all([writer,approver]);
  assert.ok(errors.some(e=>e?.code==='40P01'),'expected actual deadlock detection, not a timeout');
  await Promise.allSettled([same.query('rollback'),approval.query('rollback')]);
  // Synthetic fail-fast alternative, not a production trigger.
  await setup.query('drop trigger synthetic_guard on public.synthetic_work');
  await setup.query("create function public.synthetic_try_guard() returns trigger language plpgsql as 'begin if not pg_try_advisory_xact_lock(hashtextextended(OLD.company_id::text,319847)) then raise exception using errcode=''55P03'', message=''synthetic company busy''; end if; return NEW; end'");
  await setup.query('create trigger synthetic_try before update on public.synthetic_work for each row execute function public.synthetic_try_guard()');
  await approval.query('begin');
  await approval.query(sql,[a]);
  await same.query('begin');
  await same.query("set local statement_timeout='2s'");
  await assert.rejects(() => same.query("update public.synthetic_work set v='should fail' where company_id=$1 and v='prior writer'",[a]),e => e.code === '55P03');
  await same.query('rollback');
  await other.query('begin');
  await other.query("set local statement_timeout='2s'");
  const otherResult = await other.query("update public.synthetic_work set v='other changed' where company_id=$1 and v='other company'",[b]);
  assert.equal(otherResult.rowCount,1);
  await other.query('commit');
  const approvalResult = await approval.query("update public.synthetic_work set v='approval changed' where company_id=$1 and v='prior writer'",[a]);
  assert.equal(approvalResult.rowCount,1);
  await approval.query('rollback');
  // Negative controls: an UPDATE-only OLD-company guard cannot cover other
  // write operations or moves into a company locked by an approver.
  await approval.query('begin');
  await approval.query(sql,[a]);
  await same.query('begin');
  await same.query("set local statement_timeout='2s'");
  const inserted=await same.query("insert into public.synthetic_work values($1,'unguarded insert')",[a]);
  assert.equal(inserted.rowCount,1);
  const deleted=await same.query("delete from public.synthetic_work where company_id=$1 and v='unguarded insert'",[a]);
  assert.equal(deleted.rowCount,1);
  const moved=await same.query("update public.synthetic_work set company_id=$1 where company_id=$2 and v='other changed'",[a,b]);
  assert.equal(moved.rowCount,1);
  await same.query('commit');
  const observed=await approval.query("select count(*)::int as n from public.synthetic_work where company_id=$1 and v='other changed'",[a]);
  assert.equal(observed.rows[0].n,1);
  await approval.query('rollback');
  console.log('PASS: negative controls reproduce INSERT, DELETE and destination-company move bypass');
  // Test-only improvement: cover all three row operations and both companies
  // on a move. Try-lock (rather than wait) avoids row/advisory inversion.
  // This still does not establish production table coverage or retry safety.
  await setup.query('drop trigger synthetic_try on public.synthetic_work');
  await setup.query(`create function public.synthetic_all_write_guard() returns trigger
    language plpgsql as $guard$
    declare company uuid;
    begin
      for company in select distinct x from unnest(array[
        case when TG_OP <> 'INSERT' then OLD.company_id end,
        case when TG_OP <> 'DELETE' then NEW.company_id end
      ]) as ids(x) where x is not null order by x loop
        if not pg_try_advisory_xact_lock(hashtextextended(company::text,319847)) then
          raise exception using errcode='55P03', message='synthetic company busy';
        end if;
      end loop;
      if TG_OP = 'DELETE' then return OLD; else return NEW; end if;
    end $guard$`);
  await setup.query('create trigger synthetic_all_write before insert or update or delete on public.synthetic_work for each row execute function public.synthetic_all_write_guard()');
  await setup.query("insert into public.synthetic_work values($1,'move source')",[b]);
  await approval.query('begin');
  await approval.query(sql,[a]);
  for (const [query,params] of [
    ["insert into public.synthetic_work values($1,'blocked insert')",[a]],
    ["delete from public.synthetic_work where company_id=$1 and v='prior writer'",[a]],
    ["update public.synthetic_work set company_id=$1 where company_id=$2 and v='move source'",[a,b]],
    ["update public.synthetic_work set company_id=$1 where company_id=$2 and v='prior writer'",[b,a]],
  ]) {
    await same.query('begin');
    await same.query("set local statement_timeout='2s'");
    await assert.rejects(() => same.query(query,params),e => e.code === '55P03');
    await same.query('rollback');
  }
  await other.query('begin');
  await other.query("set local statement_timeout='2s'");
  await other.query("insert into public.synthetic_work values($1,'unrelated insert')",[b]);
  await other.query("update public.synthetic_work set v='unrelated changed' where company_id=$1 and v='unrelated insert'",[b]);
  await other.query("delete from public.synthetic_work where company_id=$1 and v='unrelated changed'",[b]);
  await other.query('commit');
  await approval.query('rollback');
  // Indirect scope hazard: rows such as report workers have no company_id.
  // ON DELETE CASCADE fires the child trigger after the parent is no longer
  // visible to the same transaction. A fail-closed lookup must roll back the
  // whole delete, rather than silently use no lock or guess a company.
  await setup.query('create table public.synthetic_parent(id uuid primary key,company_id uuid not null)');
  await setup.query('create table public.synthetic_child(parent_id uuid references public.synthetic_parent(id) on delete cascade, value text)');
  await setup.query(`create function public.synthetic_child_scope() returns trigger
    language plpgsql as $child$
    declare cid uuid;
    begin
      select p.company_id into cid from public.synthetic_parent p where p.id=OLD.parent_id;
      if cid is null then raise exception using errcode='55000',message='unknown synthetic company scope'; end if;
      if not pg_try_advisory_xact_lock(hashtextextended(cid::text,319847)) then
        raise exception using errcode='55P03',message='synthetic company busy';
      end if;
      return OLD;
    end $child// Synthetic isolation experiment. Never use against an application database.
import assert from 'node:assert/strict';
import pg from 'pg';
const url = new URL(process.env.FIXTURE_URL || 'http://invalid');
if (process.env.CI !== 'true' || url.protocol !== 'postgresql:' ||
    url.hostname !== '127.0.0.1' || url.port !== '5432' ||
    url.pathname !== '/sko_lock_fixture' ||
    Object.keys(process.env).some(k => /^SUPABASE_(ACCESS_TOKEN|DB_PASSWORD|URL|SERVICE_ROLE_KEY|SECRET_KEY|PROJECT_REF)$/.test(k)))
  throw Error('isolated CI fixture only');
const clients = Array.from({length: 4}, () => new pg.Client({connectionString:url.toString()}));
const [setup, approval, same, other] = clients;
const sql = "select pg_advisory_xact_lock(hashtextextended($1::text, 319847))";
try {
  await Promise.all(clients.map(c => c.connect()));
  const exists = await setup.query("select to_regclass('public.synthetic_work') as t");
  assert.equal(exists.rows[0].t, null);
  await setup.query("create table public.synthetic_work(company_id uuid not null, v text not null)");
  const a = '10000000-0000-0000-0000-000000000001';
  const b = '10000000-0000-0000-0000-000000000002';

  // Writer obtains the same company lock BEFORE any write. Other company can
  // write immediately, same company times out; no production trigger exists.
  await approval.query('begin');
  await approval.query(sql,[a]);
  await other.query('begin');
  await other.query("set local lock_timeout='750ms'");
  await other.query(sql,[b]);
  await other.query('insert into public.synthetic_work values($1,$2)',[b,'other company']);
  await other.query('commit');
  await same.query('begin');
  await same.query("set local lock_timeout='300ms'");
  await assert.rejects(() => same.query(sql,[a]), e => e.code === '55P03');
  await same.query('rollback');
  await approval.query('rollback');

  // Lock waits until a cooperating pending writer commits; a READ COMMITTED
  // query executed after acquisition observes its insertion.
  await same.query('begin');
  await same.query(sql,[a]);
  await same.query('insert into public.synthetic_work values($1,$2)',[a,'prior writer']);
  await approval.query('begin');
  const acquired=approval.query(sql,[a]);
  await same.query('commit');
  await acquired;
  const current=await approval.query('select count(*)::int as n from public.synthetic_work where company_id=$1',[a]);
  assert.equal(current.rows[0].n,1);
  await approval.query('rollback');

  // An unmodified direct write ignores advisory locks entirely: this is an
  // explicit release blocker, not evidence that the design is deployable.
  await approval.query('begin');
  await approval.query(sql,[a]);
  await same.query('begin');
  await same.query("set local lock_timeout='750ms'");
  await same.query('insert into public.synthetic_work values($1,$2)',[a,'bypass']);
  await same.query('commit');
  const bypass=await approval.query("select count(*)::int as n from public.synthetic_work where company_id=$1 and v='bypass'",[a]);
  assert.equal(bypass.rows[0].n,1);
  await approval.query('rollback');
  // A row trigger that takes the company advisory lock may be too late:
  // UPDATE owns the tuple before BEFORE ROW executes. The approver owns the
  // advisory lock first and then tries to update the same tuple. This is a
  // negative control, not a proposed production trigger.
  await setup.query(`create function public.synthetic_row_guard() returns trigger
    language plpgsql as $body$ begin
    perform pg_advisory_xact_lock(hashtextextended(NEW.company_id::text,319847));
    return NEW; end $body$`
);
  await setup.query('create trigger synthetic_guard before update on public.synthetic_work for each row execute function public.synthetic_row_guard()');
  const writerPid=(await same.query('select pg_backend_pid() as pid')).rows[0].pid;
  await approval.query('begin');
  await approval.query("set local statement_timeout='5s'");
  await approval.query("set local deadlock_timeout='100ms'");
  await approval.query(sql,[a]);
  await same.query('begin');
  await same.query("set local statement_timeout='5s'");
  await same.query("set local deadlock_timeout='100ms'");
  const writer= same.query("update public.synthetic_work set v='writer' where company_id=$1 and v='prior writer'",[a]).then(()=>null,e=>e);
  let blocked=false;
  for (let i=0;i<40;i++) {
    const blockers=(await setup.query('select pg_blocking_pids($1) as pids',[writerPid])).rows[0].pids;
    if (blockers.length) {blocked=true;break;}
    await new Promise(resolve=>setTimeout(resolve,25));
  }
  assert.equal(blocked,true,'writer never waited on advisory lock');
  const approver=approval.query("update public.synthetic_work set v='approver' where company_id=$1 and v='prior writer'",[a]).then(()=>null,e=>e);
  const errors=await Promise.all([writer,approver]);
  assert.ok(errors.some(e=>e?.code==='40P01'),'expected actual deadlock detection, not a timeout');
  await Promise.allSettled([same.query('rollback'),approval.query('rollback')]);
  // Synthetic fail-fast alternative, not a production trigger.
  await setup.query('drop trigger synthetic_guard on public.synthetic_work');
  await setup.query("create function public.synthetic_try_guard() returns trigger language plpgsql as 'begin if not pg_try_advisory_xact_lock(hashtextextended(OLD.company_id::text,319847)) then raise exception using errcode=''55P03'', message=''synthetic company busy''; end if; return NEW; end'");
  await setup.query('create trigger synthetic_try before update on public.synthetic_work for each row execute function public.synthetic_try_guard()');
  await approval.query('begin');
  await approval.query(sql,[a]);
  await same.query('begin');
  await same.query("set local statement_timeout='2s'");
  await assert.rejects(() => same.query("update public.synthetic_work set v='should fail' where company_id=$1 and v='prior writer'",[a]),e => e.code === '55P03');
  await same.query('rollback');
  await other.query('begin');
  await other.query("set local statement_timeout='2s'");
  const otherResult = await other.query("update public.synthetic_work set v='other changed' where company_id=$1 and v='other company'",[b]);
  assert.equal(otherResult.rowCount,1);
  await other.query('commit');
  const approvalResult = await approval.query("update public.synthetic_work set v='approval changed' where company_id=$1 and v='prior writer'",[a]);
  assert.equal(approvalResult.rowCount,1);
  await approval.query('rollback');
  // Negative controls: an UPDATE-only OLD-company guard cannot cover other
  // write operations or moves into a company locked by an approver.
  await approval.query('begin');
  await approval.query(sql,[a]);
  await same.query('begin');
  await same.query("set local statement_timeout='2s'");
  const inserted=await same.query("insert into public.synthetic_work values($1,'unguarded insert')",[a]);
  assert.equal(inserted.rowCount,1);
  const deleted=await same.query("delete from public.synthetic_work where company_id=$1 and v='unguarded insert'",[a]);
  assert.equal(deleted.rowCount,1);
  const moved=await same.query("update public.synthetic_work set company_id=$1 where company_id=$2 and v='other changed'",[a,b]);
  assert.equal(moved.rowCount,1);
  await same.query('commit');
  const observed=await approval.query("select count(*)::int as n from public.synthetic_work where company_id=$1 and v='other changed'",[a]);
  assert.equal(observed.rows[0].n,1);
  await approval.query('rollback');
  console.log('PASS: negative controls reproduce INSERT, DELETE and destination-company move bypass');
  // Test-only improvement: cover all three row operations and both companies
  // on a move. Try-lock (rather than wait) avoids row/advisory inversion.
  // This still does not establish production table coverage or retry safety.
  await setup.query('drop trigger synthetic_try on public.synthetic_work');
  await setup.query(`create function public.synthetic_all_write_guard() returns trigger
    language plpgsql as $guard$
    declare company uuid;
    begin
      for company in select distinct x from unnest(array[
        case when TG_OP <> 'INSERT' then OLD.company_id end,
        case when TG_OP <> 'DELETE' then NEW.company_id end
      ]) as ids(x) where x is not null order by x loop
        if not pg_try_advisory_xact_lock(hashtextextended(company::text,319847)) then
          raise exception using errcode='55P03', message='synthetic company busy';
        end if;
      end loop;
      if TG_OP = 'DELETE' then return OLD; else return NEW; end if;
    end $guard$`);
  await setup.query('create trigger synthetic_all_write before insert or update or delete on public.synthetic_work for each row execute function public.synthetic_all_write_guard()');
  await setup.query("insert into public.synthetic_work values($1,'move source')",[b]);
  await approval.query('begin');
  await approval.query(sql,[a]);
  for (const [query,params] of [
    ["insert into public.synthetic_work values($1,'blocked insert')",[a]],
    ["delete from public.synthetic_work where company_id=$1 and v='prior writer'",[a]],
    ["update public.synthetic_work set company_id=$1 where company_id=$2 and v='move source'",[a,b]],
    ["update public.synthetic_work set company_id=$1 where company_id=$2 and v='prior writer'",[b,a]],
  ]) {
    await same.query('begin');
    await same.query("set local statement_timeout='2s'");
    await assert.rejects(() => same.query(query,params),e => e.code === '55P03');
    await same.query('rollback');
  }
  await other.query('begin');
  await other.query("set local statement_timeout='2s'");
  await other.query("insert into public.synthetic_work values($1,'unrelated insert')",[b]);
  await other.query("update public.synthetic_work set v='unrelated changed' where company_id=$1 and v='unrelated insert'",[b]);
  await other.query("delete from public.synthetic_work where company_id=$1 and v='unrelated changed'",[b]);
  await other.query('commit');
  await approval.query('rollback');
);
  await setup.query('create trigger synthetic_child_guard before delete on public.synthetic_child for each row execute function public.synthetic_child_scope()');
  const parentId = '20000000-0000-0000-0000-000000000001';
  await setup.query('insert into public.synthetic_parent values($1,$2)',[parentId,a]);
  await setup.query("insert into public.synthetic_child values($1,'indirect')",[parentId]);
  await same.query('begin');
  await assert.rejects(() => same.query('delete from public.synthetic_parent where id=$1',[parentId]), e=>e.code==='55000');
  await same.query('rollback');
  const parentCount=await setup.query('select count(*)::int as n from public.synthetic_parent where id=$1',[parentId]);
  const childCount=await setup.query('select count(*)::int as n from public.synthetic_child where parent_id=$1',[parentId]);
  assert.equal(parentCount.rows[0].n,1);
  assert.equal(childCount.rows[0].n,1);
  console.log('PASS: cascade without parent scope fails closed and restores parent and child');

  console.log('PASS: synthetic all-write guard rejects both move directions, insert and delete while another company proceeds');
  console.log('PASS: synthetic try-lock fails promptly; other company and approver proceed');
  console.log('PASS: row trigger lock inversion produces 40P01');
  console.log('PASS: cooperative same-company serialization; other company proceeds; direct-write bypass reproduced');
} finally {
  await Promise.allSettled(clients.map(c=>c.end()));
}
