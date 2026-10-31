// Copy-only extension: retain original fixture/launcher and every SQL source.
import fs from 'node:fs/promises';
import path from 'node:path';
import {createHash,randomUUID} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
if(process.argv[3]==='postgres'){
 const url=new URL(process.env.SKO_CONSENT_FIXTURE_URL);
 if(!['postgres:','postgresql:'].includes(url.protocol)||url.hostname!=='127.0.0.1'||url.port!=='5432'
  ||url.pathname!=='/sko_document_consent_fixture'||url.username!=='postgres'||url.password!=='fixture-only'||url.search)throw Error('isolated pinned localhost fixture required');
}
const root=path.resolve(fileURLToPath(new URL('../../',import.meta.url)));
const directory=path.join(root,'docs/review/site-order-outgoing-consent');
const fixturePath=path.join(directory,'fixture.mjs'),launcherPath=path.join(directory,'verify.mjs');
const source=await fs.readFile(fixturePath,'utf8'),launcher=await fs.readFile(launcherPath,'utf8');
const sha=s=>createHash('sha256').update(s).digest('hex');
if(sha(source)!=='e339792faad67357a0e8373164a6db80fd495a9ffe266df891bee088a773eff4'
 ||sha(launcher)!=='fc84599af564d1aa1d2fa1f80aff1a122fcea9f789c2253e333a8cb17c2f3481')throw Error('frozen original fixture/launcher changed');
const patches=[];
const replace=(text,before,after)=>{if(text.split(before).length!==2)throw Error('composition anchor changed');patches.push({before,after});return text.replace(before,after);};
const loadAnchor=" await db.exec(await read('docs/review/site-order-outgoing/prepare-operation.sql.review-only'));";
let modified=replace(source,loadAnchor,loadAnchor+`
 const fullBeforeTargets=await q("select jsonb_agg(to_jsonb(p)order by p.oid)v from pg_proc p where p.oid is distinct from to_regprocedure('site_order_outgoing_private.registered_targets(uuid,uuid,integer)')");
 await db.exec(await read('docs/review/site-order-outgoing/registered-targets.sql.review-only'));
 check(await q("select jsonb_agg(to_jsonb(p)order by p.oid)v from pg_proc p where p.oid is distinct from to_regprocedure('site_order_outgoing_private.registered_targets(uuid,uuid,integer)')"),fullBeforeTargets);
`);
modified=replace(modified,' const make=async n=>',' let registeredTrade;\n const make=async n=>');
modified=replace(modified,"outgoing_context($1,$2)v',[site,trade]", "outgoing_context($1,$2)v',[site,registeredTrade]");
modified=replace(modified,' const params=x=>[site,x.doc,x.local,trade,x.request];',' const params=x=>[site,x.doc,x.local,registeredTrade,x.request];');
const phaseAnchor="  const x=await make(100);await prepare(x);const p=await preview(x);";
modified=replace(modified,phaseAnchor,`
  const selectedDirectory=await q('select site_order_outgoing_private.registered_targets($1,null,50)v',[site]);
  check(selectedDirectory.company_id,A);check(selectedDirectory.actor_id,UA);check(selectedDirectory.session_id,sid);
  check(selectedDirectory.read_only,true);check(selectedDirectory.can_send,false);check(selectedDirectory.entries.length,1);
  registeredTrade=selectedDirectory.entries[0].id;check(registeredTrade,trade);
  const fromDirectory=await make(88000);
  const targetRows=await q("select jsonb_build_object('trades',(select jsonb_agg(to_jsonb(t)order by id)from public.trade_companies t),'connections',(select jsonb_agg(to_jsonb(t)order by parent_company_id,child_company_id)from private.company_connections t),'sessions',(select jsonb_agg(to_jsonb(t)order by id)from auth.sessions t),'members',(select jsonb_agg(to_jsonb(t)order by company_id,user_id)from public.company_members t),'flags',(select jsonb_agg(to_jsonb(t)order by feature_key)from private.master_feature_settings t))v");
  const targets=()=>q('select site_order_outgoing_private.registered_targets($1,null,50)v',[site]);
  const cases=[
   [()=>db.query(\"update private.master_feature_settings set enabled=false where feature_key='site_order_documents'\"),/master_feature_disabled/],
   [()=>db.query(\"update public.company_members set role='worker' where company_id=$1 and user_id=$2\",[A,UA]),/standalone_company_management_required/],
   [()=>db.query('update public.company_members set company_id=$1 where company_id=$2 and user_id=$3',[B,A,UA]),/registered_targets_own_site_required/,/site_manager_registered_direction_required/],
   [()=>db.query(\"update auth.sessions set not_after=clock_timestamp()-interval '1 second' where id=$1\",[sid]),/reauthentication_required/],
  ];
  let composedTargetNegatives=0;
  for(const [change,pattern,preparePattern=pattern]of cases){
   for(const [action,wanted] of [[targets,pattern],[()=>prepare(fromDirectory),preparePattern]]){
    await db.exec('begin');
    try{await change();await denied(action,wanted);composedTargetNegatives++;}finally{await db.exec('rollback');}
   }
  }
  await denied(()=>q('select site_order_outgoing_private.prepare_order($1,$2,$3,$4,$5,$6,$7::jsonb)v',[site,id(88100),id(88101),id(88102),id(88103),fromDirectory.context.connection_fingerprint,JSON.stringify(fromDirectory.body)]),/site_manager_registered_direction_required/);
  composedTargetNegatives++;
  check(await q("select jsonb_build_object('trades',(select jsonb_agg(to_jsonb(t)order by id)from public.trade_companies t),'connections',(select jsonb_agg(to_jsonb(t)order by parent_company_id,child_company_id)from private.company_connections t),'sessions',(select jsonb_agg(to_jsonb(t)order by id)from auth.sessions t),'members',(select jsonb_agg(to_jsonb(t)order by company_id,user_id)from public.company_members t),'flags',(select jsonb_agg(to_jsonb(t)order by feature_key)from private.master_feature_settings t))v"),targetRows);
  check(await catalog(),before);
`+phaseAnchor+`
  check(await q('select trade_company_id::text v from site_order_outgoing_private.prepared_operations where request_id=$1',[x.request]),registeredTrade);
  console.log(JSON.stringify({registered_targets_in_full_actual_composition:true,selected_returned_trade_used_for_prepare:true,negative_cases:composedTargetNegatives,new_unconditional_permission_helper_replacements:false,real_gotrue:false,production_changed:false}));
`);
// Mechanical reverse of the exact five permitted replacements reconstructs
// the original byte-for-byte; original files themselves are never rewritten.
let reversed=modified;
for(const patch of [...patches].reverse()){
 if(reversed.split(patch.after).length!==2)throw Error('extension reverse anchor changed');
 reversed=reversed.replace(patch.after,patch.before);
}
if(reversed!==source||patches.length!==5)throw Error('unexpected fixture modification');
const token=randomUUID(),fixtureName='.targets-'+token+'.mjs',launchName='.target-launch-'+token+'.mjs';
const newFixture=path.join(directory,fixtureName),newLauncher=path.join(directory,launchName);
const launchAnchor="new URL('./fixture.mjs',import.meta.url)";
if(launcher.split(launchAnchor).length!==2)throw Error('launcher fixture anchor changed');
const created=new Set();
const writeOwned=async(file,contents)=>{const handle=await fs.open(file,'wx',0o600);created.add(file);try{await handle.writeFile(contents);}finally{await handle.close();}};
try{
 await writeOwned(newFixture,modified);
 await writeOwned(newLauncher,launcher.replace(launchAnchor,`new URL(${JSON.stringify('./'+fixtureName)},import.meta.url)`));
 const result=spawnSync(process.execPath,[newLauncher,...process.argv.slice(2)],{env:process.env,stdio:'inherit'});
 if(result.error)throw result.error;if(result.status!==0)throw Error('composed targets verification failed');
}finally{
 for(const file of created)await fs.rm(file,{force:true});
 if(sha(await fs.readFile(fixturePath))!==sha(source)||sha(await fs.readFile(launcherPath))!==sha(launcher))throw Error('original verifier files changed');
}
