// Synthetic in-memory PostgreSQL only. No backend/Storage/network access.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
const {PGlite} = await import(pathToFileURL(process.argv[2]).href);
const db = new PGlite();
const id = n => `10000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const [company, otherCompany, owner, manager, employee, target] = [1,2,3,4,5,6].map(id);
const candidate = await fs.readFile(new URL('../docs/candidates/document_requirement_archive_20261021.sql.review-only', import.meta.url), 'utf8');
try {
 await db.exec(`create role authenticated;create schema auth;
 create function auth.uid() returns uuid language sql stable as $$select current_setting('test.uid')::uuid$$;
 create table company_members(company_id uuid,user_id uuid,role text);
 create table document_requirements(id uuid primary key,company_id uuid not null,name text not null,
 scope text not null check(scope in ('internal','upstream','both')),upstream_name text not null default '',
 company_template_id uuid,is_required boolean not null default true,expiry_required boolean not null default false,
 renewal_reminder_days integer not null default 30,is_active boolean not null default true,sort_order integer not null default 0,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(company_id,scope,upstream_name,name));
 create table worker_document_statuses(id uuid primary key,requirement_id uuid references document_requirements(id) on delete cascade,attachment_path text);
 create table document_submissions(id uuid primary key,requirement_id uuid references document_requirements(id),previous jsonb,status text);
 create table document_history(id integer,requirement_id uuid,path text);
 create table sent_snapshot(id integer,snapshot jsonb);
 alter table document_requirements enable row level security;
 grant usage on schema auth to authenticated;grant select on company_members to authenticated;
 grant select,insert,update,delete on document_requirements to authenticated;
 create policy existing_read on document_requirements for select to authenticated using(exists(select 1 from company_members m where m.company_id=document_requirements.company_id and m.user_id=auth.uid()));
 create policy existing_manage on document_requirements for all to authenticated using(exists(select 1 from company_members m where m.company_id=document_requirements.company_id and m.user_id=auth.uid() and m.role in ('owner','admin','manager')))
 with check(exists(select 1 from company_members m where m.company_id=document_requirements.company_id and m.user_id=auth.uid() and m.role in ('owner','admin','manager')));
 create policy account_deletion_access_guard on document_requirements as restrictive for all to authenticated using(current_setting('test.account',true) is distinct from 'blocked') with check(current_setting('test.account',true) is distinct from 'blocked');`);
 await db.query("insert into company_members values($1,$2,'owner'),($1,$3,'manager'),($1,$4,'employee')",[company,owner,manager,employee]);
 await db.query("insert into document_requirements(id,company_id,name,scope,upstream_name)values($1,$2,'同名書類','both','会社A'),($3,$2,'同名書類','upstream','会社B')",[target,company,id(7)]);
 await db.query('insert into worker_document_statuses values($1,$2,$3)',[id(8),target,'retained/photo.jpg']);
 await db.query("insert into document_submissions values($1,$2,'{\"saved\":\"original\"}','pending')",[id(9),target]);
 await db.query('insert into document_history values(1,$1,$2)',[target,'retained/photo.jpg']);
 await db.exec("insert into sent_snapshot values(1,'{\"name\":\"同名書類\",\"path\":\"retained/photo.jpg\"}')");
 const evidence = async () => Promise.all(['worker_document_statuses','document_submissions','document_history','sent_snapshot'].map(async table => (await db.query(`select to_jsonb(t) v from ${table} t`)).rows));
 const before = await evidence();
 const catalog = async () => (await db.query("select polname,polcmd,polpermissive,pg_get_expr(polqual,polrelid) qual,pg_get_expr(polwithcheck,polrelid) chk from pg_policy where polrelid='document_requirements'::regclass order by polname")).rows;
 const policies = await catalog();
 const unique = (await db.query("select pg_get_constraintdef(oid) d from pg_constraint where conrelid='document_requirements'::regclass and contype='u'")).rows;
 await db.exec(candidate);
 assert.deepEqual(await catalog(), policies);
 assert.deepEqual((await db.query("select pg_get_constraintdef(oid) d from pg_constraint where conrelid='document_requirements'::regclass and contype='u'")).rows, unique);
 assert.deepEqual(await evidence(), before);
 await assert.rejects(db.exec(candidate), e => e.code === '55000');await db.exec('rollback');
 const row = async () => (await db.query('select to_jsonb(d) v from document_requirements d where id=$1',[target])).rows[0].v;
 const initial = await row();
 const archive = async (snapshot, cid=company) => (await db.query("update document_requirements d set archived_at=now(),is_active=false,updated_at=now() where company_id=$1 and id=$2 and to_jsonb(d)=$3::jsonb returning id",[cid,target,JSON.stringify(snapshot)])).rows;
 await db.exec(`set test.uid='${employee}';set role authenticated`);
 assert.equal((await archive(initial)).length,0);await db.exec('reset role');
 assert.deepEqual(await row(), initial);
 await db.exec(`set test.uid='${manager}';set role authenticated`);
 assert.equal((await archive(initial,otherCompany)).length,0);
 await db.exec("set test.account='blocked'");assert.equal((await archive(initial)).length,0);await db.exec("set test.account='allowed';reset role");
 // An old writer changes content without advancing updated_at: full-content CAS
 // must reject the stale deletion rather than archiving the new configuration.
 await db.query("update document_requirements set is_required=false where id=$1",[target]);
 assert.equal((await archive(initial)).length,0);
 const current = await row();assert.equal(current.updated_at,initial.updated_at);
 await db.exec(`set test.uid='${manager}';set role authenticated`);
 assert.equal((await archive(current)).length,1);await db.exec('reset role');
 const archived = await row();assert.equal(archived.is_active,false);assert.ok(archived.archived_at);
 assert.equal((await db.query('select count(*)::int n from document_requirements where is_active')).rows[0].n,1);
 assert.equal((await db.query('select count(*)::int n from document_requirements where archived_at is null')).rows[0].n,1);
 assert.deepEqual(await evidence(),before);
 // Existing ON CONFLICT inference is unchanged; no new ID, reparenting or
 // duplicate unique-key row is silently created when the archived key exists.
 assert.equal((await db.query("insert into document_requirements(id,company_id,name,scope,upstream_name) values($1,$2,'同名書類','both','会社A') on conflict(company_id,scope,upstream_name,name) do nothing returning id",[id(10),company])).rows.length,0);
 await assert.rejects(db.query('update document_requirements set is_active=true where id=$1',[target]),e=>e.code==='23514');
 await db.query('update document_requirements set archived_at=null,is_active=false,updated_at=now() where id=$1 and to_jsonb(document_requirements)=$2::jsonb',[target,JSON.stringify(archived)]);
 assert.equal((await row()).id,target);assert.equal((await row()).is_active,false);
 assert.deepEqual(await evidence(),before);
 console.log('PASS requirement archive: unchanged unique/ON CONFLICT/RLS, role/company/account rejection, full-content stale CAS, hidden/archive distinction, same-ID restore, status/pending/photo/history/sent preservation');
} finally { await db.close(); }
