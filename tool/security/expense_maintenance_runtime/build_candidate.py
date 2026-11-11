"""Offline-only deterministic transformation of the pinned reviewed converter."""
import hashlib
from pathlib import Path
SOURCE_SHA='725ff2533539c63759c92c0bbc45d37c131fa431c421fd76deb127bdff2604d7'
AUTH=""" if auth.uid() is null or private.account_access_allowed() is not true
 or not exists(select 1 from public.company_members where company_id=cid and user_id=auth.uid() and role::text in ('owner','admin','manager'))
 then raise exception 'explicit conversion actor denied' using errcode='42501';end if;"""
def build(raw:bytes)->str:
 if hashlib.sha256(raw).hexdigest()!=SOURCE_SHA:raise ValueError('unknown_converter_source')
 source=raw.decode();body=source[source.index('create function private.convert_payment_expense_v1_draft('):]
 assert body.count(AUTH)==1
 body=body.replace('private.convert_payment_expense_v1_draft','private.convert_payment_expense_v1_maintenance')
 body=body.replace('rollout_reference text\n)', 'rollout_reference text, expected_db_login text, authority_original jsonb, authorization_reference text\n)')
 body=body.replace('private.expense_payment_direction_conversions','private.expense_payment_maintenance_conversions')
 body=body.replace(' next_revision integer; next_snapshot jsonb;', ' next_revision integer; next_snapshot jsonb; authority_now jsonb;')
 auth=""" -- Maintenance authorization is explicit DB-operator authority, never an app JWT.
 if current_user<>'postgres' or session_user::text is distinct from expected_db_login
 or expected_db_login is null or expected_db_login !~ '^cli_login_[A-Za-z0-9_]+(\\.ztktgquxvcxcjxtluspu)?$'
 or auth.uid() is not null
 or nullif(current_setting('request.jwt.claims',true),'') is not null
 or nullif(current_setting('request.jwt.claim.sub',true),'') is not null
 or nullif(current_setting('request.jwt.claim.role',true),'') is not null
 then raise exception 'maintenance database executor denied' using errcode='42501';end if;
 if authorization_reference is null or authorization_reference !~ '^[0-9a-f]{64}$'
 or jsonb_typeof(authority_original) is distinct from 'object'
 or authority_original->>'company_id' is distinct from cid::text
 or authority_original->>'role' is distinct from 'owner'
 or coalesce(authority_original->>'user_id','')!~'^[0-9a-fA-F-]{36}$'
 then raise exception 'maintenance authorization original required';end if;"""
 body=body.replace(AUTH,auth)
 anchor=" perform private.expense_cost_scope_lock(cid,'subcontractor',subject,first_day);"
 body=body.replace(anchor,anchor+"""
 -- Membership is a preserved authorization original, not the executing identity.
 select to_jsonb(m) into strict authority_now from public.company_members m
 where m.company_id=cid and m.user_id=(authority_original->>'user_id')::uuid for share;
 if authority_now is distinct from authority_original then raise exception 'maintenance authority original changed';end if;""")
 anchor=' if audit.company_id is distinct from cid'
 body=body.replace(anchor,""" if audit.execution_kind is distinct from 'maintenance'
 or audit.db_session_user::text is distinct from session_user::text
 or audit.db_current_user::text is distinct from current_user::text
 or audit.authorization_reference is distinct from authorization_reference
 or audit.authority_original is distinct from authority_original
 or audit.company_id is distinct from cid""")
 body=body.replace('before_row,after_row,backup_reference,rollout_reference,actor_id)', 'before_row,after_row,backup_reference,rollout_reference,execution_kind,db_session_user,db_current_user,authority_original,authorization_reference)')
 body=body.replace('to_jsonb(result),backup_reference,rollout_reference,auth.uid());', "to_jsonb(result),backup_reference,rollout_reference,'maintenance',session_user,current_user,authority_original,authorization_reference);")
 body=body.replace('(uuid,uuid,uuid,date,integer,jsonb,text,text,text) from', '(uuid,uuid,uuid,date,integer,jsonb,text,text,text,text,jsonb,text) from')
 body=body.replace('from public,anon,authenticated;', 'from public,anon,authenticated,service_role;')
 # Original function body remains untouched except the declared auth/audit boundary.
 prefix="""-- REVIEW ONLY; offline generated from converter SHA256 SOURCE_SHA.
-- Separate maintenance identity. No JWT/GUC fabrication, public API or grants.
-- This does not enable gates, verify rollout, invoke conversion or alter old audit.
BEGIN;
CREATE TABLE private.expense_payment_maintenance_conversions(
 document_id uuid primary key,company_id uuid not null,subject_id uuid not null,
 month date not null,source_revision integer not null,source_hash text not null,
 before_row jsonb not null,after_row jsonb not null,backup_reference text not null,
 rollout_reference text not null,execution_kind text not null check(execution_kind='maintenance'),
 db_session_user name not null,db_current_user name not null,
 authority_original jsonb not null,authorization_reference text not null check(authorization_reference~'^[0-9a-f]{64}$'),
 converted_at timestamptz not null default now());
ALTER TABLE private.expense_payment_maintenance_conversions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.expense_payment_maintenance_conversions FROM public,anon,authenticated,service_role;
CREATE FUNCTION private.expense_payment_maintenance_audit_immutable()RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$BEGIN RAISE EXCEPTION 'maintenance conversion original and receipt are immutable';END $$;
REVOKE ALL ON FUNCTION private.expense_payment_maintenance_audit_immutable()FROM public,anon,authenticated,service_role;
CREATE TRIGGER expense_payment_maintenance_audit_immutable BEFORE UPDATE OR DELETE ON private.expense_payment_maintenance_conversions
FOR EACH ROW EXECUTE FUNCTION private.expense_payment_maintenance_audit_immutable();
""".replace('SOURCE_SHA',SOURCE_SHA)
 original_start=source.index('create function private.convert_payment_expense_v1_draft(')
 original_body=source[source.index('as $$',original_start)+5:source.index('$$;',original_start)]
 original_md5=hashlib.md5(original_body.encode()).hexdigest()
 guard="""DO $source_guard$ BEGIN
 IF to_regprocedure('private.convert_payment_expense_v1_draft(uuid,uuid,uuid,date,integer,jsonb,text,text,text)') IS NOT NULL
 AND (SELECT md5(prosrc)FROM pg_proc WHERE oid=to_regprocedure('private.convert_payment_expense_v1_draft(uuid,uuid,uuid,date,integer,jsonb,text,text,text)')) IS DISTINCT FROM 'MD5'
 THEN RAISE EXCEPTION 'existing original converter source differs';END IF;
 END $source_guard$;
""".replace('MD5',original_md5)
 return prefix.replace('CREATE TABLE private.expense_payment_maintenance_conversions(',guard+'CREATE TABLE private.expense_payment_maintenance_conversions(')+body+'\nCOMMIT;\n'
if __name__=='__main__':
 here=Path(__file__).resolve().parent
 result=build((here/'source/conversion.sql').read_bytes())
 (here/'maintenance.sql.review-only').write_text(result)
 print('offline_candidate_sha256='+hashlib.sha256(result.encode()).hexdigest())
