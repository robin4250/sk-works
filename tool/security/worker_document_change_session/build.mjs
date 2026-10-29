// Review-only successor; historical candidate is never edited or deployed here.
import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
const source=await fs.readFile('docs/candidates/worker_document_change_20261019.sql.review-only','utf8');
assert.equal(createHash('sha256').update(source).digest('hex'),'67fa8b1b2ca8027aa39a08211942c8ee00f353bc92ac27ca5432134e565f9dc5');
let sql=source;
const replace=(old,next)=>{assert.equal(sql.split(old).length,2,`Historical anchor changed: ${old.slice(0,60)}`);sql=sql.replace(old,()=>next);};
replace('begin;','begin;\n'+await fs.readFile('tool/security/worker_document_change_session/preamble.sql','utf8'));
replace('target_id uuid not null,requested_by uuid not null,','target_id uuid not null,requested_by uuid not null,created_session_id uuid not null default private.require_reauthentication_session(),');
replace('previous jsonb not null,next_row jsonb not null','previous jsonb not null,next_row jsonb not null,session_id uuid not null default private.require_reauthentication_session()');
replace('(x.requested_by=actor or private.worker_document_change_can_manage(x.company_id) or private.worker_document_change_can_review(x.company_id))', '(private.worker_document_change_can_access(x.company_id,x.worker_id) and (x.requested_by=actor or private.worker_document_change_can_manage(x.company_id)))');
const manageStart='create function private.worker_document_change_can_manage(cid uuid) returns boolean';
const guardStart='create function private.worker_document_change_guard() returns trigger';
const a=sql.indexOf(manageStart),b=sql.indexOf(guardStart);assert.ok(a>0&&b>a);
sql=sql.slice(0,a)+await fs.readFile('tool/security/worker_document_change_session/authority.sql','utf8')+'\n'+sql.slice(b);
replace(" if auth.uid() is null or not coalesce(private.account_access_allowed(),false) then",` -- OFF, INSERT, DELETE and unrelated targets preserve existing product behavior.
 if not private.worker_document_change_enabled() then if tg_op='DELETE' then return old;else return new;end if;end if;
 if tg_op='DELETE' then return old;end if;
 if tg_op='INSERT' then return new;end if;
 if not exists(select 1 from private.worker_document_changes r where r.target_id=old.id and r.status in ('draft','pending')) then return new;end if;
 -- Status/original-only product updates (including own bank synchronization) stay with existing RLS.
 if (to_jsonb(new)-array['status','original_verified','updated_at','updated_by'])=
    (to_jsonb(old)-array['status','original_verified','updated_at','updated_by']) then return new;end if;
 perform private.require_reauthentication_session();
 if auth.uid() is null or not coalesce(private.account_access_allowed(),false) then`);
replace(" if tg_op='DELETE' then raise exception 'Saved document deletion requires a separate preservation review' using errcode='42501';end if;",'');
replace('if found and ticket.actor_id=auth.uid() and ticket.transaction_id=txid_current()', 'if found and ticket.actor_id=auth.uid() and ticket.transaction_id=txid_current()\n  and ticket.session_id=private.require_reauthentication_session()');
replace(" if actor is null or not coalesce(private.account_access_allowed(),false) or jsonb_typeof(p_data) is distinct from 'object' then",` perform private.require_reauthentication_session();
 if not private.worker_document_change_enabled() then raise sqlstate '42501' using message='Document change unavailable';end if;
 -- Serialize permission changes and scope changes through the operation commit.
 perform 1 from public.company_members where user_id=actor for share;
 perform 1 from public.member_feature_permissions where user_id=actor for share;
 if actor is null or not coalesce(private.account_access_allowed(),false) or jsonb_typeof(p_data) is distinct from 'object' then`);
replace("  if not(can_manage or can_own) or not exists(select 1 from public.document_requirements d", "  perform 1 from public.workers where id=official.worker_id and company_id=official.company_id and status='active' for share;\n  if not found then raise sqlstate '42501' using message='Document worker unavailable';end if;\n  perform 1 from public.document_requirements where id=official.requirement_id and company_id=official.company_id and is_active for share;\n  if not found then raise sqlstate '42501' using message='Document requirement unavailable';end if;\n  if not(can_manage or can_own) or not exists(select 1 from public.document_requirements d");
replace(" if not exists(select 1 from public.workers w where w.id=r.worker_id and w.company_id=r.company_id)"," perform 1 from public.workers where id=r.worker_id and company_id=r.company_id and status='active' for share;\n if not found then raise sqlstate '42501' using message='Document worker unavailable';end if;\n perform 1 from public.document_requirements where id=r.requirement_id and company_id=r.company_id and is_active for share;\n if not found then raise sqlstate '42501' using message='Document requirement unavailable';end if;\n perform 1 from public.company_members where company_id=r.company_id and user_id=r.requested_by for share;\n perform 1 from public.member_feature_permissions where company_id=r.company_id and user_id=r.requested_by for share;\n if not exists(select 1 from public.workers w where w.id=r.worker_id and w.company_id=r.company_id and w.status='active')");
replace("(w.user_id=r.requested_by or m.role::text in ('owner','admin','manager'))", "(w.user_id=r.requested_by or m.role::text in ('owner','admin','manager') or exists(select 1 from public.member_feature_permissions p where p.company_id=m.company_id and p.user_id=m.user_id and p.can_manage_people))");
replace(' can_manage:=private.worker_document_change_can_manage(r.company_id);',` if p_action<>'detail' then
  perform 1 from public.workers where id=r.worker_id and company_id=r.company_id and status='active' for share;
  if not found then raise sqlstate '42501' using message='Document worker unavailable';end if;
  perform 1 from public.document_requirements where id=r.requirement_id and company_id=r.company_id and is_active for share;
  if not found then raise sqlstate '42501' using message='Document requirement unavailable';end if;
 end if;
 can_manage:=private.worker_document_change_can_manage(r.company_id);`);
// Immutable audit per successful explicit operation, including a fresh valid SID.
replace('create function public.worker_document_change(p_action text,p_data jsonb) returns jsonb',`create function public.worker_document_change(p_action text,p_data jsonb) returns jsonb`);
replace(" if r.requested_by<>actor and not can_manage and not can_review then raise exception 'Request unavailable' using errcode='42501';end if;", " if not private.worker_document_change_can_access(r.company_id,r.worker_id) or (r.requested_by<>actor and not can_manage and not can_review) then raise exception 'Request unavailable' using errcode='42501';end if;");
const wrapper='language sql security invoker set search_path=\'\' as $$select private.worker_document_change(p_action,p_data)$$;';
assert.ok(sql.includes(wrapper), 'Public wrapper anchor');
replace(wrapper,`language plpgsql security definer set search_path='' as $$
 declare result jsonb;sid uuid;begin
 sid:=private.require_reauthentication_session();
 result:=private.worker_document_change(p_action,p_data);
 if p_action in ('prepare','submit','approve','reject','cancel') then
  insert into private.worker_document_change_events(request_id,actor_id,session_id,action)
   values((result->>'id')::uuid,auth.uid(),sid,p_action);
 end if;
 return result;end $$;`);
replace('grant execute on function private.worker_document_change(text,jsonb) to authenticated;', 'revoke all on function private.worker_document_change(text,jsonb) from authenticated,service_role;');
replace('commit;',await fs.readFile('tool/security/worker_document_change_session/seal.sql','utf8')+'\ncommit;');
await fs.writeFile('docs/candidates/worker_document_change_session_20261029/install.sql.review-only',sql);
console.log('PASS exact historical-source anchors; generated OFF successor only');
