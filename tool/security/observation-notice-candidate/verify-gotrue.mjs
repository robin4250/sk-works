// Generate an isolated companion from the exact checked-in collector fixture.
// It starts only the original disposable local stack and deletes the generated
// script after completion. No hosted project or real identities are accepted.
import {readFile,writeFile,unlink} from 'node:fs/promises';
import {createHash,randomBytes} from 'node:crypto';
import {spawn,spawnSync} from 'node:child_process';
import path from 'node:path';
const repo=process.cwd(),dir=path.join(repo,'docs/review/collector-current-core-20261026');
const original=await readFile(path.join(dir,'verify_gotrue.mjs'),'utf8');
if(createHash('sha256').update(original).digest('hex')!=='07089675a14d016b347cab10e17fa1cf54b43b3363f36df450b9c3e7803d91a6')throw Error('Collector fixture source changed; review before reuse');
let s=original.replace("import {createHash,randomBytes,randomUUID} from 'node:crypto';","import {createHash,createHmac,randomBytes,randomUUID} from 'node:crypto';");
const before="await db.query(await read('./install-off.sql.review-only'));";
if(s.split(before).length!==2)throw Error('Collector setup marker mismatch');
s=s.replace(before,before+"await db.query(await fs.readFile(path.join(repo,'tool/security/observation-notice-candidate/install.sql.review-only'),'utf8'));" );
const start=s.indexOf(" phase='actual-service-issuer';"), end=s.indexOf(" phase='actual-edge-runtime';");
if(start<0||end<=start)throw Error('Old unrelated issuer checks marker mismatch');
s=s.slice(0,start)+s.slice(end);
const oldStart=s.indexOf(" phase='registration-baseline';"), oldEnd=s.indexOf("}catch(error){",oldStart);
if(oldStart<0||oldEnd<=oldStart)throw Error('Existing reader checks marker mismatch');
const addition=String.raw`
 phase='notice-config';
 const company=(await db.query('select company_id from public.company_members where user_id=$1',[users.master.id])).rows[0].company_id;
 const collector=randomUUID(),eventId=randomUUID(),eventKey=randomBytes(32),now=new Date(),stamp=now.getTime();
 const event={event_id:eventId,collector_id:collector,occurred_at:now.toISOString(),event_kind:'current_lure_touched',generation:1,correlation_key:hash('synthetic notice only'),key_epoch:now.toISOString().slice(0,10)};
 const raw=Buffer.from(JSON.stringify(event)),signature=createHmac('sha256',eventKey).update('sko-collector-v2\n'+collector+'\n1\n'+stamp+'\n').update(raw).digest('hex');
 await db.query("insert into private.security_collector_keys values($1,1,$2,true,null,clock_timestamp()-interval '1 minute',clock_timestamp()+interval '1 day')",[collector,eventKey]);
 await db.query('update private.security_collector_control set ingest_enabled=true');
 await db.query('update security_observation_notice_private.config set enabled=true,collector_id=$1,company_id=$2,master_id=$3',[collector,company,users.master.id]);
 await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({role:'service_role'})]);
 const envelope={collector_id:collector,key_version:1,timestamp:stamp,body_base64:raw.toString('base64'),signature};
 eq((await db.query('select public.ingest_signed_security_collector_event($1)v',[envelope])).rows[0].v,eventId,'Real pgcrypto collector evidence accepted');
 await db.query("notify pgrst,'reload schema'");
 let publishReady=false;for(let i=0;i<70;i++){const z=await rpc('publish_security_observation_notice',{p_event_id:eventId},undefined,true);if(z.status===200){eq(await z.json(),'available','Fixed service-only publication');publishReady=true;break;}await wait(200);}eq(publishReady,true,'Actual PostgREST service publication ready');
 eq((await rpc('publish_security_observation_notice',{p_event_id:eventId},master.access_token)).status===200,false,'Authenticated user cannot impersonate delivery service');
 eq((await rpc('publish_security_observation_notice',{p_event_id:eventId},undefined,true)).status,200,'Service retries without duplicate');
 phase='actual-notice-master-proof';
 let readyNotice=false;for(let i=0;i<70;i++){const z=await rpc('read_security_observation_notices',{p_proof:'bad'},master.access_token);if(z.status===403){readyNotice=true;break;}await wait(200);}eq(readyNotice,true,'Actual PostgREST sees notice RPC');
 const p=await edge(master.access_token);eq(p.status,200,'Real Edge issues session-bound collector proof');const noticeProof=await p.json();
 eq((await rpc('read_security_observation_notices',{p_proof:noticeProof.proof},logins.otherMaster.access_token)).status,403,'Other real Master denied');
 eq((await rpc('read_security_observation_notices',{p_proof:noticeProof.proof},logins.normalAdmin.access_token)).status,403,'Ordinary administrator denied');
 const r=await rpc('read_security_observation_notices',{p_proof:noticeProof.proof},master.access_token);eq(r.status,200,'Current Master with real GoTrue JWT and one-use proof reads notice');const got=await r.json();eq(got.events.length,1,'Exactly one synthetic notice');eq(got.events[0].event_id,eventId,'Original event identity preserved');eq(got.attack_confirmed,false,'Not a confirmed attack');eq('correlation_key' in got.events[0],false,'Correlation secret not returned');
 eq((await rpc('read_security_observation_notices',{p_proof:noticeProof.proof},master.access_token)).status,403,'Proof reuse rejected');
 const actionResponse=await edge(master.access_token);eq(actionResponse.status,200,'Real proof issued for explicit review');const actionProof=await actionResponse.json();
 const commandId=randomUUID(),command={p_event_id:eventId,p_action:'false_positive',p_reason:'fixture reviewed',p_expected_revision:1,p_command_id:commandId,p_proof:actionProof.proof};
 eq((await rpc('update_security_observation_notice',command,logins.otherMaster.access_token)).status,403,'Different Master cannot review other owner notice');
 const action=await rpc('update_security_observation_notice',command,master.access_token);eq(action.status,200,'Real Master reviews notice with actual proof');eq((await action.json()).revision,2,'Review version advanced');
 const retry=await rpc('update_security_observation_notice',{...command,p_proof:''},master.access_token);eq(retry.status,200,'Same command retry survives lost ACK');eq((await retry.json()).replayed,true,'Retry reports original durable action');
 eq((await rpc('update_security_observation_notice',{...command,p_reason:'different'},master.access_token)).status===200,false,'Same command with changed reason refused');
 const revokedProofResponse=await edge(master.access_token);eq(revokedProofResponse.status,200,'Second proof issued before session revocation');const revokedProof=await revokedProofResponse.json();
 await db.query('delete from auth.sessions where id=$1',[masterSid]);eq((await rpc('read_security_observation_notices',{p_proof:revokedProof.proof},master.access_token)).status,403,'Revoked actual session denied');
 console.log(JSON.stringify({pass:true,checks,real_local_gotrue:true,real_edge_runtime:true,real_postgrest:true,actual_collector_hmac:true,notice_master_proof:true,revoked_session_denied:true,production_changed:false,real_notification:false}));
`;
s=s.slice(0,oldStart)+addition+s.slice(oldEnd);
if(process.env.SKO_NOTICE_EMIT_ONLY==='1'){const p=spawnSync(process.execPath,['--check','--input-type=module'],{input:s,encoding:'utf8'});if(p.status!==0){process.stderr.write(p.stderr);process.exit(1);}console.log('Generated GoTrue fixture syntax verified; no local stack started');process.exit(0);}
const temp=path.join(dir,'notice-fixture-'+randomBytes(8).toString('hex')+'.mjs');
try{await writeFile(temp,s,{mode:0o600,flag:'wx'});const code=await new Promise((resolve,reject)=>{const p=spawn(process.execPath,[temp],{stdio:'inherit',cwd:repo,env:process.env});p.once('error',reject);p.once('exit',code=>resolve(code));});if(code!==0)process.exitCode=1;}finally{await unlink(temp).catch(()=>{});}
