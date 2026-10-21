// Extends the disposable core fixture. Financial mutation uses verbatim existing
// migration functions/triggers; no fake financial-approval writer is substituted.
import fs from 'node:fs/promises';
export async function verifyInvoiceConfirmation(db,c){
 const {id,A,B,UA,UB,UV,INV,CUSTOMER,actor,q,check,deny,localId,render}=c;
 const read=p=>fs.readFile('supabase/migrations/'+p,'utf8');
 const fn=(s,name)=>{const start=s.indexOf('create or replace function '+name+'(');if(start<0)throw Error('source function absent: '+name);const end=s.indexOf('$$;',s.indexOf('$$',start)+2);if(end<0)throw Error('source delimiter absent');return s.slice(start,end+3);};
 await actor(UA);await db.exec("update private.company_connections set status='accepted';create table auth.users(id uuid primary key);create table user_profiles(user_id uuid,display_name text)");
 await db.query('insert into auth.users values($1),($2),($3)',[UA,UB,UV]);
 const workflow=await read('20261005081500_invoice_approval_workflow.sql');
 await db.exec(workflow.slice(0,workflow.indexOf('-- Existing companies begin')));
 await db.exec(fn(workflow,'private.ensure_invoice_approval_rows'));
 const policy=await read('20261007221757_invoice_stamp_policy_and_approval_history.sql');
 await db.exec(policy.slice(0,policy.indexOf('create or replace function')));
 for(const name of ['public.invoice_approval_status_rows_v2','public.approve_invoice','private.invalidate_invoice_approval','private.invoice_material_change_trigger'])await db.exec(fn(policy,name));
 await db.exec('create trigger invoice_material_change_after_update after update on invoices for each row execute function private.invoice_material_change_trigger()');
 const snapshot=await read('20261009012730_company_seal_document_snapshots.sql');
 await db.exec(snapshot.slice(snapshot.indexOf('create function private.preserve_document_company_seal_snapshot'),snapshot.indexOf('create trigger zz_company_seal_snapshot')));
 await db.exec('create trigger zz_company_seal_snapshot before insert or update on invoices for each row execute function private.preserve_document_company_seal_snapshot();alter table invoices drop column invoice_seal_frozen');
 await db.exec(await read('20261011031108_invoice_draft_seal_finalization.sql'));
 await db.exec(await read('20261009010422_invoice_explicit_stamp_surname_snapshot.sql'));
 // Synthetic surrounding schema/clock, not synthetic approval behavior.
 await db.exec(`create table trade_companies(id uuid primary key,company_id uuid,customer_id uuid,linked_company_id uuid,trade_role text,link_status text);
 create function private.fixture_invoice_clock() returns trigger language plpgsql as $$begin new.updated_at:=clock_timestamp();return new;end $$;
 create trigger aa_fixture_invoice_clock before update on invoices for each row execute function private.fixture_invoice_clock()`);
 await db.query("insert into trade_companies values($1,$2,$3,$4,'customer','linked')",[id(80),A,CUSTOMER,B]);
 await db.query('insert into invoice_approvers(company_id,position,user_id,created_by) values($1,1,$2,$2)',[A,UA]);
 await db.exec(await fs.readFile('docs/candidates/trade_document_invoice_confirmation_20261021.sql.review-only','utf8'));
 const oldFinal=await q('select to_jsonb(i) v from invoices i where id=$1',[INV]);
 const prepare=async(num)=>{
  await actor(UA);const parent=id(200+num),doc=id(300+num),local=localId(doc,A);
  await db.query("insert into invoices(id,company_id,customer_id,billing_period_start,billing_period_end,updated_at,status,grand_total,tax,snapshot) values($1,$2,$3,'2026-10-01','2026-10-31',clock_timestamp(),'draft',110000,10000,'{}')",[parent,A,CUSTOMER]);
  await db.query('select private.ensure_invoice_approval_rows($1)',[parent]);
  const source=await q('select updated_at::text v from invoices where id=$1',[parent]);
  const workspace=await q("select public.trade_document_attachment_workspace('invoice',$1,$2) v",[parent,source]);
  const payload={...workspace.defaults,issue_date:'2026-10-21',work_name:'合成承認工事',work_address:'東京都',tax_amount_yen:10000,intro_text:'合成請負',payment_conditions:'翌月末',notes:'',issuer:{...workspace.defaults.issuer,representative_name:'甲代表'},counterparty:{...workspace.defaults.counterparty,corporate_number:'2222222222222'}};
  await q("select public.save_trade_document_attachment('invoice',$1,$2,0,$3::jsonb) v",[parent,source,JSON.stringify(payload)]);
  const body={...payload,issuer_company_id:A,counterparty_company_id:B,transaction_id:doc};delete body.company_seal_snapshot;delete body.company_seal_enabled;
  await q("select trade_document_consent_private.prepare_document($1,$2,$3,0,$4::jsonb,'invoice',$5,$6,1) v",[doc,A,B,JSON.stringify(body),parent,source]);
  await db.query('select trade_document_consent_private.bind_local($1,$2,$3)',[doc,A,local]);
  return {parent,doc,local};
 };
 const preview=x=>q('select trade_document_consent_private.preview_confirmation($1,$2,1) v',[x.local,A]);
 const confirm=(x,p,rid=id(500+Number(x.doc.slice(-3))),financial=true,seal=true)=>q('select trade_document_consent_private.confirm_local_document($1,$2,1,$3::jsonb,$4,$5,$6) v',[x.local,A,JSON.stringify(p),rid,financial,seal]);
 const state=x=>q(`select jsonb_build_object('parent',to_jsonb(i),'approvals',(select jsonb_agg(to_jsonb(a)) from invoice_approvals a where invoice_id=i.id),
 'audit',(select count(*) from invoice_approval_audit where invoice_id=i.id),'revision',(select to_jsonb(r) from trade_document_consent_private.revisions r where document_id=$2 and revision=1),
 'consents',(select count(*) from trade_document_consent_private.consents where document_id=$2),'events',(select count(*) from trade_document_consent_private.events where document_id=$2),
 'receipts',(select count(*) from trade_document_consent_private.financial_receipts where document_id=$2),'primitive_receipts',(select count(*) from trade_document_consent_private.receipts)) v from invoices i where id=$1`,[x.parent,x.doc]);
 const x=await prepare(1),p=await preview(x),before=await state(x);
 await deny(()=>confirm(x,p,id(600),true,false),/both explicit/);check(await state(x),before);
 const approved=await confirm(x,p);check([approved.financial_approved,approved.seal_consent_recorded],[true,true]);
 const after=await state(x);check(after.parent.invoice_seal_frozen,true);check(after.approvals[0].status,'approved');check(after.audit,1);check(after.consents,1);check(after.receipts,1);check(after.revision.binding,before.revision.binding);
 check(await confirm(x,p),approved);check(await state(x),after);
 const issued=await render(x.doc,1,A);await actor(UB);await db.query('select trade_document_consent_private.bind_local($1,$2,$3)',[x.doc,B,localId(x.doc,B)]);check(await render(x.doc,1,B),issued);
 await deny(()=>confirm({...x,local:localId(x.doc,B)},p),/issuer|permission|own/);
 await actor(UA);await db.query('update invoices set grand_total=grand_total+1 where id=$1',[x.parent]);await deny(()=>render(x.doc,1,A),/changed/);check(await render(x.doc,1,A,true),issued);
 const stale=await prepare(2),sp=await preview(stale);await db.query('update invoices set grand_total=grand_total+1 where id=$1',[stale.parent]);const staleState=await state(stale);await deny(()=>confirm(stale,sp),/changed/);check(await state(stale),staleState);
 const final=await prepare(3),fp=await preview(final);await db.query('select public.approve_invoice($1)',[final.parent]);const finalState=await state(final);await deny(()=>confirm(final,fp),/unfinalized/);check(await state(final),finalState);
 const surname=await prepare(4);await db.query('insert into private.invoice_stamp_surname_rollout values($1,true)',[A]);const np=await preview(surname),ns=await state(surname);
 await deny(()=>confirm(surname,np),/explicit surname/);check(await state(surname),ns);
 await db.query('select public.set_invoice_stamp_surname($1,$2)',[surname.parent,'合成']);
 await deny(()=>confirm(surname,np),/source changed/);const namePreview=await preview(surname);check(namePreview.approval_function,'approve_invoice_with_stamp_surname');await confirm(surname,namePreview);check(await q('select surname v from private.invoice_stamp_surname_snapshots where invoice_id=$1',[surname.parent]),'合成');
 await db.query('update private.invoice_stamp_surname_rollout set enabled=false where company_id=$1',[A]);
 const late=await prepare(5),lp=await preview(late),ls=await state(late);
 await db.exec("create function private.fixture_late_failure()returns trigger language plpgsql as $$begin raise exception 'fixture late receipt failure';end $$;create trigger fixture_late_failure before insert on trade_document_consent_private.financial_receipts for each row execute function private.fixture_late_failure()");
 await deny(()=>confirm(late,lp),/late receipt failure/);check(await state(late),ls);await db.exec('drop trigger fixture_late_failure on trade_document_consent_private.financial_receipts');
 const rights=await prepare(6),rp=await preview(rights),rs=await state(rights);await db.exec("select set_config('test.invoice_manage','false',false)");await deny(()=>confirm(rights,rp),/permission/);check(await state(rights),rs);await db.exec("select set_config('test.invoice_manage','true',false)");
 await actor(UV);await deny(()=>preview(rights),/permission/);await actor(UA);
 const prior=await prepare(7);await db.query("insert into invoice_approvals(invoice_id,company_id,approver_user_id,position) values($1,$2,$3,2)",[prior.parent,A,UV]);await deny(()=>preview(prior),/other assigned/);
 check(await q('select to_jsonb(i) v from invoices i where id=$1',[INV]),oldFinal);
 await deny(()=>db.query('update trade_document_consent_private.consents set actor_id=actor_id where document_id=$1',[x.doc]),/immutable/);
 await deny(()=>db.query('delete from trade_document_consent_private.financial_receipts where document_id=$1',[x.doc]),/immutable/);
 await db.exec('set role authenticated');await deny(()=>preview(x),/permission denied/);await db.exec('reset role');
 console.log('PASS invoice adapter: verbatim existing approve/surname/freeze source, atomic success and two later-stage rollback paths, CAS, finalized protection, issuer/received local copies; no public/API/UI/monthly-payment rollout');
}
