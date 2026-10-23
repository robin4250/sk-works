// Operator-only offline preparation. No connection, deployment or data repair here.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
export const oldFunctions = [
  'private.expense_cost_finalize()',
  'private.read_expense_document(text,uuid)',
  'private.refresh_automatic_payment_certificate(uuid,uuid,date)',
];
export const newFunctions = [
  'private.expense_cost_direction_v2_enabled(uuid)',
  'private.expense_payment_v2_envelope(uuid,uuid,uuid,date,integer,numeric,jsonb)',
  'private.expense_payment_v2_guard()',
  'private.expense_payment_direction_capability(uuid)',
  'public.expense_payment_direction_capability(uuid)',
];
const signatures=[...oldFunctions,...newFunctions].map(s=>`'${s}'`).join(',');
export const catalogSql=`select jsonb_build_object(
 'functions',coalesce((select jsonb_agg(jsonb_build_object(
 'signature',n.nspname||'.'||p.proname||'('||replace(oidvectortypes(p.proargtypes),', ',',')||')','oid',p.oid,'definition',pg_get_functiondef(p.oid),
 'owner',pg_get_userbyid(p.proowner),'acl',p.proacl,'config',p.proconfig,
 'definer',p.prosecdef,'volatility',p.provolatile,'parallel',p.proparallel,
 'strict',p.proisstrict,'leakproof',p.proleakproof,'source_md5',md5(p.prosrc)) order by n.nspname,p.proname,oidvectortypes(p.proargtypes))
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where p.oid in(select to_regprocedure(s) from unnest(array[${signatures}]) s)),'[]'::jsonb),
 'triggers',coalesce((select jsonb_agg(jsonb_build_object('oid',t.oid,'table',t.tgrelid::regclass::text,
 'name',t.tgname,'enabled',t.tgenabled,'definition',pg_get_triggerdef(t.oid,true),'function',p.oid::regprocedure::text,
 'source_md5',md5(p.prosrc)) order by t.tgrelid::regclass::text,t.tgname)
 from pg_trigger t join pg_proc p on p.oid=t.tgfoid where not t.tgisinternal and
 (t.tgrelid='public.payment_certificates'::regclass or t.tgfoid=to_regprocedure('private.expense_cost_finalize()'))),'[]'::jsonb),
 'event_triggers',coalesce((select jsonb_agg(jsonb_build_object('oid',e.oid,'name',e.evtname,'event',e.evtevent,
 'enabled',e.evtenabled,'tags',e.evttags,'function',p.oid::regprocedure::text,'source_md5',md5(p.prosrc)) order by e.evtname)
 from pg_event_trigger e join pg_proc p on p.oid=e.evtfoid),'[]'::jsonb)) value`;
export async function captureCodeCheckpoint(db){return (await db.query(catalogSql)).rows[0].value;}
function quote(value,tag){assert(!value.includes(`$${tag}$`),'checkpoint delimiter collision');return `$${tag}$${value}$${tag}$`;}
const md5=s=>createHash('md5').update(s).digest('hex');
export function buildCodeRestore(before,after){
 assert.deepEqual(before.functions.map(f=>f.signature).sort(),[...oldFunctions].sort(),'original scope differs');
 assert.deepEqual(after.functions.map(f=>f.signature).sort(),[...oldFunctions,...newFunctions].sort(),'deployed scope differs');
 assert.equal(after.functions.find(f=>f.signature===newFunctions[0]).source_md5,md5('select false'),'only default OFF deployment can be restored');
 for(const f of before.functions){
  const next=after.functions.find(n=>n.signature===f.signature);
  const metadata=x=>Object.fromEntries(Object.entries(x).filter(([k])=>!['definition','source_md5'].includes(k)));
  assert.deepEqual(metadata(next),metadata(f),'existing function metadata changed');
 }
 assert.deepEqual(after.event_triggers,before.event_triggers,'event trigger checkpoint differs');
 const expectedAfter=quote(JSON.stringify(after),'expected_expense_after');
 const expectedBefore=quote(JSON.stringify(before),'expected_expense_before');
 const restore=before.functions.map((f,i)=>`EXECUTE ${quote(f.definition,'expense_original_'+i)};`).join('\n');
 return `-- REVIEW ONLY: code-only rollback before any v2 records exist. No CASCADE or business DML.\nDO $expense_restore$\nDECLARE actual jsonb;\nBEGIN\n PERFORM set_config('lock_timeout','5s',true);\n LOCK TABLE public.payment_certificates IN SHARE ROW EXCLUSIVE MODE;\n SELECT value INTO actual FROM (${catalogSql}) c;\n IF actual IS DISTINCT FROM ${expectedAfter}::jsonb THEN RAISE EXCEPTION 'expense deployed checkpoint differs';END IF;\n IF EXISTS(SELECT 1 FROM public.payment_certificates WHERE snapshot?'expense_cost_direction_v2' OR snapshot?'expense_cost_basis') THEN RAISE EXCEPTION 'v2 documents require v2 code';END IF;\n IF to_regclass('private.expense_payment_direction_conversions') IS NOT NULL OR to_regprocedure('private.convert_payment_expense_v1_draft(uuid,uuid,uuid,date,integer,jsonb,text,text,text)') IS NOT NULL THEN RAISE EXCEPTION 'conversion installation requires separate recovery review';END IF;\n ${restore}\n DROP FUNCTION public.expense_payment_direction_capability(uuid);\n DROP FUNCTION private.expense_payment_direction_capability(uuid);\n DROP TRIGGER expense_direction_v2_guard ON public.payment_certificates;\n DROP FUNCTION private.expense_payment_v2_guard();\n DROP FUNCTION private.expense_payment_v2_envelope(uuid,uuid,uuid,date,integer,numeric,jsonb);\n DROP FUNCTION private.expense_cost_direction_v2_enabled(uuid);\n SELECT value INTO actual FROM (${catalogSql}) c;\n IF actual IS DISTINCT FROM ${expectedBefore}::jsonb THEN RAISE EXCEPTION 'expense original checkpoint not restored';END IF;\nEND $expense_restore$;`;
}
