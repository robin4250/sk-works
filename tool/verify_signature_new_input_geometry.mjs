// Native PostgreSQL17 only. Exact three deployed writer bodies; synthetic auth,
// permission, finalization admission and neutral financial surroundings are explicit.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
const url=new URL(process.env.SKO_SIGNATURE_INPUT_FIXTURE_URL??'postgres://invalid');
assert.equal(process.env.CI,'true');assert.equal(url.hostname,'127.0.0.1');assert.equal(url.username,'postgres');
assert.equal(url.password,'fixture-only');assert.equal(url.pathname,'/sko_signature_input_fixture');assert.equal(url.port,'5432');
assert.ok(['postgres:','postgresql:'].includes(url.protocol));assert.equal(url.search,'');assert.equal(url.hash,'');
assert.ok(!Object.keys(process.env).some(k=>/^SUPABASE_(ACCESS_TOKEN|DB_PASSWORD|URL|SERVICE_ROLE_KEY|SECRET_KEY|PROJECT_REF)$/.test(k)));
const pg=(await import(process.argv[2])).default;const db=new pg.Client({connectionString:url.href});
assert.equal(db.connectionParameters.host,'127.0.0.1');assert.equal(db.connectionParameters.database,'sko_signature_input_fixture');assert.equal(db.connectionParameters.user,'postgres');assert.equal(Number(db.connectionParameters.port),5432);await db.connect();
let checks=0,phase='setup',sequence=100;const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const q=async(s,p=[]) => (await db.query(s,p)).rows[0]?.v;const eq=(a,b,m)=>{assert.deepEqual(a,b,m);checks++;};
const reject=async(action,pattern=/signature|invalid|input|range|json/i)=>{await assert.rejects(action,pattern);checks++;};
const owner=id(1),foreign=id(2),company=id(3),otherCompany=id(4),worker=id(5);
const root='docs/review/signature-new-input-geometry/';
const fixture=JSON.parse(await readFile(root+'source-fixtures.json','utf8'));const sourcePins=JSON.parse(await readFile(root+'source-pins.json','utf8'));
const cases=JSON.parse(await readFile('test/fixtures/signature_input_geometry_cases.json','utf8')).cases;
const good={strokes:[[{x:.2,y:.3},{x:.4,y:.5}]]};const dots={strokes:[[{x:.2,y:.3}],[{x:.7,y:.8}]]};
const md5=s=>createHash('md5').update(s).digest('hex');
const body=s=>s.match(/AS \$function\$([\s\S]*?)\$function\$/)[1];
const signature=f=>f.schema+'.'+f.proname+'('+f.identity.split(',').map(x=>x.trim().split(' ').slice(1).join(' ')).join(',')+')';
async function call(actor,sql,args=[]){await q("select set_config('fixture.actor',$1,false)",[actor??'']);await db.query('set role authenticated');try{return await q(sql,args);}finally{await db.query('reset role');}}
async function snapshot(){return q(`select jsonb_build_object('reports',(select jsonb_agg(to_jsonb(x) order by id) from daily_reports x),
 'workers',(select jsonb_agg(to_jsonb(x) order by report_id,worker_id) from daily_report_workers x),
 'entries',(select jsonb_agg(to_jsonb(x) order by id) from attendance_entries x),
 'visits',(select jsonb_agg(to_jsonb(x) order by id) from private.route_visit_reports x),
 'neutral_capture_counters',(select jsonb_agg(to_jsonb(x) order by name) from private.fixture_capture_counters x)) v`);}
async function report(){const rid=id(++sequence),site=id(10000+sequence);await db.query("insert into daily_reports(id,company_id,site_id,report_date,status,work_description) values($1,$2,$3,'2026-10-31','draft','Synthetic')",[rid,company,site]);await db.query("insert into daily_report_workers(report_id,worker_id) values($1,$2)",[rid,worker]);return rid;}
async function visit(){const rid=id(++sequence);await db.query("insert into private.route_visit_reports(id,company_id,created_by,workers,status,site_name) values($1,$2,$3,'[]','draft','Synthetic visit')",[rid,company,owner]);return rid;}
const ordinary=(rid,role,input,actor=owner)=>call(actor,'select public.save_daily_report_signature($1,$2,$3,$4::jsonb) v',[rid,role,'Synthetic signer',input]);
const route=(rid,role,input,actor=owner)=>call(actor,'select public.save_route_visit_report_signature($1,$2,$3,$4::jsonb) v',[rid,role,'Synthetic signer',input]);
const financial=(rid,input,actor=owner)=>call(actor,'select public.sign_daily_report($1,$2,$3::jsonb) v',[rid,'Synthetic signer',input]);
function inputFor(row){
 if(!row.generator)return JSON.stringify(row.value);
 const line=[{x:.1,y:.1},{x:.4,y:.5}];
 if(row.generator==='stroke_limit')return JSON.stringify({strokes:Array.from({length:257},()=>line)});
 if(row.generator==='per_stroke_point_limit')return JSON.stringify({strokes:[[...line,...Array.from({length:16383},()=>({x:.4,y:.5}))]]});
 if(row.generator==='total_point_limit')return JSON.stringify({strokes:Array.from({length:5},()=>[...line,...Array.from({length:13998},()=>({x:.4,y:.5}))])});
 if(row.generator==='payload_limit'){
  const point='{"x":0.'+'1'.repeat(128)+',"y":0.'+'2'.repeat(128)+'}';
  const raw='{"strokes":[[{"x":0.1,"y":0.1},{"x":0.4,"y":0.5},'+Array(15998).fill(point).join(',')+']]}' ;
  assert.ok(Buffer.byteLength(raw)>4194304);return raw;
 }
 throw Error('Unknown fixture generator');
}
try{
 const version=Number(await q("select current_setting('server_version_num') v"));eq(version>=170000&&version<180000,true,'Native PG17 required');
 eq(await q("select count(*)::int v from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public'"),0,'Fresh disposable database only');
 await db.query(`create role anon;create role authenticated;create role service_role;
 create schema auth;create schema private;create schema payroll_scope_private;create schema explicit_report_finalization_private;
 create schema explicit_route_finalization_private;create schema shared_daily_report_private;
 create schema checkout_report_registration_private;create schema company_checkout_allowance_private;create schema checkout_paid_hours_candidate_private;
 grant usage on schema auth,private to authenticated;
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('fixture.actor',true),'')::uuid$$;
 create function private.account_access_allowed() returns boolean language sql stable as $$select true$$;
 create table company_members(company_id uuid,user_id uuid);
 create table daily_reports(id uuid primary key,company_id uuid,site_id uuid,route_assignment_id uuid,report_date date,work_description text,status text,
 signer_name text,signature_json jsonb,signed_at timestamptz,updated_by uuid,updated_at timestamptz default now(),
 representative_signature_json jsonb,representative_signer_name text,supervisor_signature_json jsonb,supervisor_signer_name text);
 create table daily_report_workers(report_id uuid,worker_id uuid,overtime_hours numeric default 0,early_hours numeric default 0,night_hours numeric default 0,allowance_amount integer default 0,allowance_label text,work_category text default 'day',primary key(report_id,worker_id));
 create table attendance_entries(id uuid primary key default gen_random_uuid(),company_id uuid,work_date date,worker_id uuid,site_id uuid,route_assignment_id uuid,
 base_man_days numeric,overtime_hours numeric,early_hours numeric,night_hours numeric,allowance_amount integer,notes text,work_category text,
 allowance_names text[],source_report_id uuid,company_allowance_receipt_id uuid,created_by uuid,updated_by uuid,created_at timestamptz default now(),updated_at timestamptz default now());
 create table shared_daily_report_private.work_protocol(report_id uuid primary key,document_only boolean);
 create table private.route_visit_reports(id uuid primary key,company_id uuid,created_by uuid,workers jsonb,status text,site_name text,
 representative_signature_json jsonb,representative_signer_name text,supervisor_signature_json jsonb,supervisor_signer_name text,
 signed_at timestamptz,updated_at timestamptz default now(),explicit_enabled boolean default false);
 create table private.fixture_capture_counters(name text primary key,calls integer);
 insert into private.fixture_capture_counters values('enroll',0),('allowance',0),('paid_hours',0);
 create function payroll_scope_private.report_sources(uuid) returns jsonb language sql stable as $$select '{"scopes":[]}'::jsonb$$;
 create function payroll_scope_private.lock_scopes(jsonb) returns void language sql as $$select null::void$$;
 create function explicit_report_finalization_private.enroll(uuid) returns void language sql as $$update private.fixture_capture_counters set calls=calls+1 where name='enroll'$$;
 create function explicit_report_finalization_private.required(uuid) returns boolean language sql stable as $$select false$$;
 create function explicit_report_finalization_private.lock_actor(uuid) returns void language sql as $$select null::void$$;
 create function explicit_report_finalization_private.auto_confirm(uuid) returns void language sql as $$select null::void$$;
 create function explicit_report_finalization_private.assert_supervisor(uuid) returns void language sql as $$select null::void$$;
 create function shared_daily_report_private.document_mode(uuid) returns boolean language sql stable as $$select false$$;
 create function company_checkout_allowance_private.capture_report(uuid) returns jsonb language plpgsql as $$begin update private.fixture_capture_counters set calls=calls+1 where name='allowance';return '{}'::jsonb;end$$;
 create function checkout_paid_hours_candidate_private.capture_report(uuid,jsonb) returns void language sql as $$update private.fixture_capture_counters set calls=calls+1 where name='paid_hours'$$;
 create function explicit_route_finalization_private.required(uuid) returns boolean language sql stable as $$select explicit_enabled from private.route_visit_reports where id=$1$$;
 create function explicit_route_finalization_private.actor_allowed(uuid) returns boolean language sql stable as $$select created_by=auth.uid() from private.route_visit_reports where id=$1$$;
 create function explicit_route_finalization_private.lock_actor(uuid) returns void language sql as $$select null::void$$;
 create function explicit_route_finalization_private.enroll(uuid) returns void language sql as $$select null::void$$;
 create function explicit_route_finalization_private.decorate(jsonb) returns jsonb language sql immutable as $$select $1$$;`);
 await db.query('insert into company_members values($1,$2),($3,$4)',[company,owner,otherCompany,foreign]);
 for(const f of [...fixture.writers,...fixture.public_wrappers,fixture.historical_interpreter]){
  eq(md5(body(f.definition)),f.source_md5,'Exact deployed source body '+f.signature);
  await db.query(f.definition);
  const identity=signature(f);await db.query('revoke all on function '+identity+' from public,anon,authenticated,service_role');
  for(const acl of f.attributes.proacl??[]){const role=acl.split('=')[0];if(role==='postgres')continue;assert.match(role,/^(authenticated|service_role)$/);await db.query('grant execute on function '+identity+' to '+role);}
 }
 for(const f of fixture.shared_entry_points){eq(md5(body(f.definition)),f.source_md5,'Exact shared source preserved');assert.ok(f.definition.includes('perform private.save_daily_report_signature('),'Observed shared role entry converges on the validated writer');checks++;}
 const old=await report(),oldVisit=await visit(),legacyVisit=await visit();
 await db.query("update daily_reports set status='signed',signature_json=$2::jsonb,representative_signature_json=$2::jsonb,supervisor_signature_json=$2::jsonb,signer_name='Old synthetic',representative_signer_name='Old synthetic',supervisor_signer_name='Old synthetic' where id=$1",[old,JSON.stringify(dots)]);
 await db.query("update private.route_visit_reports set status='reporter_signed',explicit_enabled=true,representative_signature_json=$2::jsonb,representative_signer_name='Old synthetic' where id=$1",[oldVisit,JSON.stringify(dots)]);
 await db.query("update private.route_visit_reports set status='reporter_signed',representative_signature_json=$2::jsonb,representative_signer_name='Old synthetic' where id=$1",[legacyVisit,JSON.stringify(dots)]);
 const oldRows=await snapshot();const untouchedHistoryHash=await q("select md5(prosrc) v from pg_proc where oid='checkout_report_registration_private.has_signature(text,jsonb)'::regprocedure");
 phase='old-server-dot-acceptance-red';const red=await report();await ordinary(red,'representative',JSON.stringify(dots));
 eq(await q('select representative_signature_json v from daily_reports where id=$1',[red]),dots,'RED current server accepts isolated dots before the candidate');
 phase='install-new-input-only';const before=await snapshot();
 await db.query(await readFile(root+'install.sql.review-only','utf8'));
 eq(await snapshot(),before,'Code installation changes no original, role signature, source or neutral financial counter');
 eq(await q("select md5(prosrc) v from pg_proc where oid='checkout_report_registration_private.has_signature(text,jsonb)'::regprocedure"),untouchedHistoryHash,'Historical interpretation function remains byte-for-byte');
 eq(await q('select checkout_report_registration_private.has_signature($1,$2::jsonb) v',['Old synthetic',JSON.stringify(dots)]),true,'Old dots retain historical interpretation; no retroactive global validator change');
 const returned=await call(owner,'select public.save_route_visit_report_signature($1,$2,$3,$4::jsonb) v',[oldVisit,'reporter','Old synthetic',JSON.stringify(dots)]);
 eq(returned.representative_signature_json,dots,'Existing exact read-only route acknowledgement still returns the original dots');
 const legacyBefore=await snapshot();const legacyAck=await route(legacyVisit,'reporter',JSON.stringify(dots));eq(legacyAck.representative_signature_json,dots,'Legacy nonterminal reporter exact retry retains old dots');eq(await snapshot(),legacyBefore,'Legacy reporter read-only acknowledgement makes no write');
 eq(await q('select representative_signature_json v from daily_reports where id=$1',[old]),dots,'Historical original remains readable and unmodified');
 for(const row of cases){phase='new-input-'+row.name;const input=inputFor(row);
  for(const [name,prepare,invoke] of [
   ['ordinary-reporter',report,(rid)=>ordinary(rid,'representative',input)],
   ['ordinary-supervisor',async()=>{const rid=await report();await ordinary(rid,'representative',JSON.stringify(good));return rid;},rid=>ordinary(rid,'supervisor',input)],
   ['route-reporter',visit,rid=>route(rid,'reporter',input)],
   ['route-responsible',async()=>{const rid=await visit();await route(rid,'reporter',JSON.stringify(good));return rid;},rid=>route(rid,'responsible',input)],
   ['direct-financial',report,rid=>financial(rid,input)]]){
   const rid=await prepare(),saved=await snapshot();
   if(row.expected_server){await invoke(rid);checks++;}
   else{await reject(()=>invoke(rid));eq(await snapshot(),saved,'Rejected '+row.name+' through '+name+' changes no report/signature/receipt-source/counter');}
  }
 }
 phase='pair-envelope-and-valid-refinalization';
 const final=await report(),pair=JSON.stringify({version:3,representative:good,supervisor:good});
 await financial(final,pair);eq(await q('select status v from daily_reports where id=$1',[final]),'signed','Valid pair reaches the existing finalization writer');
 await financial(final,pair);eq(await q('select signature_json v from daily_reports where id=$1',[final]),JSON.parse(pair),'Valid re-finalization retains the exact signature JSON');
 for(const badPair of [{version:3,representative:dots,supervisor:good},{version:3,representative:good,supervisor:dots},{version:'3',representative:good,supervisor:good}]){const rid=await report(),saved=await snapshot();await reject(()=>financial(rid,JSON.stringify(badPair)));eq(await snapshot(),saved,'Invalid financial envelope cannot bypass role ink validation');}
 const oldBefore=await snapshot();await reject(()=>financial(old,JSON.stringify(dots)));eq(await snapshot(),oldBefore,'A new financial write cannot re-adopt old dots; the original is kept');
 phase='authorization-not-weakened';
 const restricted=await report(),saved=await snapshot();await reject(()=>ordinary(restricted,'representative',JSON.stringify(good),foreign),/not found|unavailable/);await reject(()=>ordinary(restricted,'representative',JSON.stringify(good),null),/authentication/);eq(await snapshot(),saved,'Existing actor/company authorization is unchanged');
 for(const role of ['authenticated','anon','service_role'])eq(await q("select has_function_privilege($1,'signature_new_input_private.require_ink(jsonb)','execute') v",[role]),false,'No new helper execute permission for '+role);
 eq(await q('select representative_signature_json v from daily_reports where id=$1',[old]),dots,'All negative/positive cases retain the old original');
 console.log(JSON.stringify({pass:true,checks,native_pg17:true,shared_fixture_cases:cases.length,actual_deployed_dot_acceptance_reproduced:true,actual_role_writers_and_direct_finalizer:true,blank_dot_repeated_short_nonfinite_huge_rejected:true,valid_roles_pair_and_refinalization:true,historical_has_signature_unchanged:true,old_original_read_and_readonly_ack_retained:true,synthetic_auth_and_neutral_financial_surroundings:true,real_gotrue:false,production_changed:false}));
}catch(error){console.error(JSON.stringify({pass:false,phase,message:error.message,code:error.code,production_changed:false}));process.exitCode=1;}
finally{await db.end();}
