import fs from 'node:fs/promises';

export async function verifySiteOrderSiteHistory(db,{id,A,B,UA,UB,UC,actor,q}) {
 let checks=0;
 const check=(value,expected)=>{if(JSON.stringify(value)!==JSON.stringify(expected))throw Error('site-history mismatch');checks++;};
 const deny=async(fn,pattern)=>{let error;try{await fn();}catch(e){error=e;}if(!error||!pattern.test(error.message))throw Error('expected '+pattern+' got '+error?.message);checks++;};
 const signed=async uid=>{await actor(uid);const sid=await q('select id v from auth.sessions where user_id=$1 order by id limit 1',[uid]);await db.query("select set_config('test.jwt',$1,false)",[JSON.stringify({sub:uid,role:'authenticated',session_id:sid})]);};
 const before=await q(`select jsonb_agg(to_jsonb(p) order by p.oid) v from pg_proc p
 where p.pronamespace in('site_order_package_private'::regnamespace,'site_order_manager_private'::regnamespace)`);
 await db.exec(await fs.readFile('docs/review/site-order-package-flow/site-history.sql.review-only','utf8'));
 const after=await q(`select jsonb_agg(to_jsonb(p) order by p.oid) v from pg_proc p
 where p.pronamespace in('site_order_package_private'::regnamespace,'site_order_manager_private'::regnamespace)
 and p.oid<>'site_order_package_private.site_history_entries(uuid,timestamptz,uuid,integer)'::regprocedure`);
 check(after,before);
 const history=(site,before=null,beforeId=null,limit=50)=>q('select site_order_package_private.site_history_entries($1,$2,$3,$4) v',[site,before,beforeId,limit]);
 await signed(UA);
 const site=await q('select j.site_id v from site_order_package_private.packages p join site_order_artifact_private.render_jobs j on j.id=p.source_job_id where p.sender_company_id=$1 order by p.created_at,p.id limit 1',[A]);
 const rows=await history(site);check(rows.length>=2,true);
 for(const row of rows){
  check(await q('select j.site_id v from site_order_package_private.packages p join site_order_artifact_private.render_jobs j on j.id=p.source_job_id where p.id=$1',[row.package_id]),site);
  check(Object.keys(row).sort(),['package_id','created_at','work_name','period_start','period_end','is_recipient','pdf_sha256'].sort());
  check(/^[0-9a-f]{64}$/.test(row.pdf_sha256),true);
 }
 const one=await history(site,null,null,1);
 const next=await history(site,one[0].created_at,one[0].package_id,1);
 check(one.length,1);check(next.length,1);check(next[0].package_id===one[0].package_id,false);
 await deny(()=>history(site,null,one[0].package_id),/cursor_invalid/);
 await deny(()=>history(site,null,null,51),/cursor_invalid/);
 const empty=id(188881);
 await db.query("insert into public.sites(id,company_id,name,status) values($1,$2,'同名でも別現場','preparation')",[empty,A]);
 check(await history(empty),[]);
 const recipientSite=await q('select accepted_site_id v from site_order_package_private.approvals where recipient_company_id=$1 order by created_at limit 1',[B]);
 await deny(()=>history(recipientSite),/not_found/);
 await signed(UB);
 const incoming=await history(recipientSite);check(incoming.length>=1,true);
 for(const row of incoming)check(row.is_recipient,true);
 await deny(()=>history(site),/not_found/);
 await db.query("update private.master_feature_settings set enabled=false where feature_key='site_order_documents'");
 check(await history(recipientSite),incoming);
 await signed(UC);await deny(()=>history(site),/not_found/);
 await signed(UA);
 await db.query("update company_members set role='worker' where user_id=$1",[UA]);
 await deny(()=>history(site),/management_required/);
 await db.query("update company_members set role='manager' where user_id=$1",[UA]);
 for(const role of ['authenticated','anon','service_role']) {
  await db.exec('set role '+role);await deny(()=>history(site),/permission denied/);await db.exec('reset role');
 }
 await db.query("update private.master_feature_settings set enabled=true where feature_key='site_order_documents'");
 console.log(JSON.stringify({site_history_checks:checks,status:'passed',synthetic_auth:true,production_applied:false}));
}
