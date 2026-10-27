// Disposable local-only GoTrue + PostgREST proof. No hosted credentials or data.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {randomBytes,randomUUID} from 'node:crypto';
const run=promisify(execFile),root=process.cwd(),parent=path.resolve(process.env.RUNNER_TEMP??'');
if(process.env.CI!=='true'||!process.env.RUNNER_TEMP||parent==='/'||process.env.SKO_INVOICE_NOTICE_AUTH_HOOK!=='contract-v1'||Object.keys(process.env).some(k=>/^SUPABASE_(ACCESS_TOKEN|DB_PASSWORD|URL|SERVICE_ROLE_KEY|SECRET_KEY|PROJECT_REF)$/.test(k)))throw Error('isolated CI without hosted credentials required');
const project='sko-invoice-approval-'+randomBytes(8).toString('hex'),workdir=path.join(parent,project);
const cli=(args,timeout=120000)=>run('npx',['--yes','supabase@2.121.0',...args,'--workdir',workdir],{cwd:root,timeout,maxBuffer:1024*1024,env:process.env});
let started=false,owned=false,db,phase='setup';
try {
 await fs.mkdir(workdir,{recursive:false,mode:0o700});owned=true;await cli(['init']);
 const file=path.join(workdir,'supabase/config.toml');let config=await fs.readFile(file,'utf8');
 config=config.replace(/^project_id = .*$/m,`project_id = "${project}"`);
 for(const [a,b] of [['54321','53911'],['54322','53912'],['54320','53910'],['54323','53913'],['54324','53914'],['54327','53917'],['54329','53919']])config=config.replaceAll(a,b);
 config=config.replace(/(\[db.seed\][\s\S]*?enabled = )true/,'$1false');await fs.writeFile(file,config,{mode:0o600});
 assert.equal((await run('docker',['ps','-a','--filter',`name=${project}`,'--format','{{.ID}}'])).stdout.trim(),'');
 phase='start';started=true;await cli(['start','--exclude','edge-runtime,realtime,storage-api,imgproxy,studio,postgres-meta,logflare,vector,supavisor'],600000);
 const status=JSON.parse((await cli(['status','--output','json'])).stdout),api=new URL(status.API_URL),database=new URL(status.DB_URL);
 assert.ok(['127.0.0.1','localhost','[::1]'].includes(api.hostname)&&api.protocol==='http:'&&api.port==='53911');
 assert.ok(['127.0.0.1','localhost','[::1]'].includes(database.hostname)&&database.port==='53912'&&database.pathname==='/postgres');
 const publicKey=status.ANON_KEY??status.PUBLISHABLE_KEY,serviceKey=status.SERVICE_ROLE_KEY??status.SECRET_KEY;
 assert.equal(typeof publicKey,'string');assert.equal(typeof serviceKey,'string');
 const pg=(await import(path.join(root,'tool/security/fixture_dependencies/node_modules/pg/lib/index.js'))).default;
 db=new pg.Client({connectionString:database.href});await db.connect();
 assert.equal((await db.query("select count(*)::int n from pg_tables where schemaname='public'")).rows[0].n,0);
 assert.equal((await db.query('select count(*)::int n from auth.users')).rows[0].n,0);
 async function request(route,{token,body,service=false,headers={}}={}) {
  const u=new URL(route,api);assert.equal(u.origin,api.origin);
  return fetch(u,{method:'POST',redirect:'error',signal:AbortSignal.timeout(20000),headers:{apikey:service?serviceKey:publicKey,...(service&&!serviceKey.startsWith('sb_'+'secret_')?{Authorization:'Bearer '+serviceKey}:{}),...(token?{Authorization:'Bearer '+token}:{}),...(body===undefined?{}:{'Content-Type':'application/json'}),...headers},...(body===undefined?{}:{body:JSON.stringify(body)})});
 }
 const users={},tokens={},password='fixture-'+randomBytes(20).toString('hex')+'!A1';
 phase='real-local-auth';
 for(const name of ['owner','admin','foreign']) {
  const created=await request('/auth/v1/admin/users',{service:true,body:{email:name+'@example.invalid',password,email_confirm:true}});assert.equal(created.status,200);users[name]=await created.json();
  const login=await request('/auth/v1/token?grant_type=password',{body:{email:users[name].email,password}});assert.equal(login.status,200);
  const session=await login.json();tokens[name]=session.access_token;const claims=JSON.parse(Buffer.from(session.access_token.split('.')[1],'base64url').toString('utf8'));
  assert.equal(claims.sub,users[name].id);assert.ok(claims.session_id);
  assert.equal((await db.query('select count(*)::int n from auth.sessions where id=$1 and user_id=$2',[claims.session_id,users[name].id])).rows[0].n,1);
 }
 phase='synthetic-notification-setup';
 await db.query(`create schema private;create schema invoice_month_close_candidate;
 create function private.account_access_allowed() returns boolean language sql stable as $$select true$$;
 create table public.company_members(company_id uuid,user_id uuid,role text);
 create table public.invoices(id uuid primary key,company_id uuid,updated_at timestamptz);
 create table public.invoice_approvals(invoice_id uuid,company_id uuid,approver_user_id uuid,status text);
 create table public.app_notifications(id uuid primary key,recipient_user_id uuid,action_key text,action_id uuid);
 create function invoice_month_close_candidate.notification_rollout_enabled() returns boolean language sql stable as $$select true$$;`);
 await db.query(await fs.readFile('reauth-source/tool/reauthentication-helper.fixture.sql','utf8'));
 const dir='docs/review/invoice-month-close/';
 await db.query(await fs.readFile(dir+'notification.sql.review-only','utf8'));
 await db.query(`create function invoice_month_close_candidate.notification_readiness(i uuid,u uuid) returns jsonb language sql as $$select jsonb_build_object('status','ready','invoice_revision',updated_at::text,'source_fingerprint',repeat('a',64)) from public.invoices where id=i$$;
 create function private.enqueue_notification(uuid,uuid,text,text,text,text,uuid) returns uuid language sql as $$select gen_random_uuid()$$;
 create function invoice_month_close_candidate.approve_from_notice(p uuid) returns boolean language plpgsql security definer set search_path='' as $$begin perform invoice_month_close_candidate.consume_notice_ticket(p);return true;end$$;`);
 await db.query(await fs.readFile(dir+'notification_delivery.sql.review-only','utf8'));
 await db.query(await fs.readFile(dir+'public_entry.sql.review-only','utf8'));
 const cid=randomUUID(),iid=randomUUID(),intent=randomUUID(),notification=randomUUID();
 await db.query("insert into public.company_members values($1,$2,'employee')",[cid,users.owner.id]);
 await db.query('insert into public.invoices values($1,$2,now())',[iid,cid]);
 await db.query("insert into public.invoice_approvals values($1,$2,$3,'pending')",[iid,cid,users.owner.id]);
 await db.query("update invoice_month_close_candidate.notice_settings set enabled=true");
 await db.query("insert into invoice_month_close_candidate.notice_intents(id,invoice_id,company_id,recipient_id,invoice_revision,source_fingerprint) select $1,id,company_id,$2,updated_at,repeat('a',64) from public.invoices where id=$3",[intent,users.owner.id,iid]);
 await db.query("insert into public.app_notifications values($1,$2,'invoice_approval',$3)",[notification,users.owner.id,iid]);
 await db.query('insert into invoice_month_close_candidate.delivery_receipts(notice_id,notification_id,recipient_id) values($1,$2,$3)',[intent,notification,users.owner.id]);
 for(const role of ['anon','authenticated','service_role']) for(const f of ['public.invoice_notice_open_candidate(uuid)','public.invoice_approve_notice_candidate(uuid)']) assert.equal((await db.query("select has_function_privilege($1,$2,'EXECUTE') allowed",[role,f])).rows[0].allowed,false);
 await db.query('grant execute on function public.invoice_notice_open_candidate(uuid),public.invoice_approve_notice_candidate(uuid) to authenticated');
 await db.query("notify pgrst,'reload schema'");
 const open=(token)=>request('/rest/v1/rpc/invoice_notice_open_candidate',{body:{p_notification:notification},token});
 const approve=(id,token)=>request('/rest/v1/rpc/invoice_approve_notice_candidate',{body:{p_ticket:id},token});
 phase='actual-jwt';let response;
 for(let i=0;i<40;i++){response=await open(tokens.owner);if(response.status!==404&&response.status!==503)break;await new Promise(r=>setTimeout(r,250));}
 assert.equal(response.status,200);let ticket=await response.json();assert.equal(ticket.notification_id,notification);assert.equal(ticket.invoice_id,iid);
 for(const t of [tokens.admin,tokens.foreign,undefined]) assert.notEqual((await open(t)).status,200);
 assert.notEqual((await approve(ticket.ticket_id,tokens.foreign)).status,200);
 assert.equal((await approve(ticket.ticket_id,tokens.owner)).status,200);
 assert.notEqual((await approve(ticket.ticket_id,tokens.owner)).status,200);
 response=await open(tokens.owner);assert.equal(response.status,200);ticket=await response.json();
 await db.query("update public.invoices set updated_at=updated_at+interval '1 second' where id=$1",[iid]);assert.notEqual((await approve(ticket.ticket_id,tokens.owner)).status,200);
 await db.query('update invoice_month_close_candidate.notice_intents n set invoice_revision=i.updated_at from public.invoices i where n.invoice_id=i.id');
 response=await open(tokens.owner);assert.equal(response.status,200);ticket=await response.json();
 response=await request('/auth/v1/logout',{token:tokens.owner});assert.equal(response.status,204);assert.notEqual((await approve(ticket.ticket_id,tokens.owner)).status,200);
 assert.equal((await db.query('select status from public.invoice_approvals where invoice_id=$1',[iid])).rows[0].status,'pending');
 console.log('PASS disposable GoTrue/PostgREST notice ticket: real session, wrong actor, stale, replay and logout; approval/readiness synthetic');
} catch(error){console.error('invoice notice isolated test failed at '+phase+': '+String(error?.message??error).slice(0,500));process.exitCode=1;}
finally {if(db)await db.end().catch(()=>{});if(started)await cli(['stop','--no-backup'],180000).catch(()=>{process.exitCode=1;});if(owned)await fs.rm(workdir,{recursive:true,force:true}).catch(()=>{process.exitCode=1;});}
