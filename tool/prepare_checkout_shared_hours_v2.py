#!/usr/bin/env python3
"""Exact v1-to-optional-v2 dispatch only; no connection or data conversion."""
import argparse
import hashlib
import importlib.util
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[1]


def functions(text):
    pattern = re.compile(r"^create(?: or replace)? function\s+([a-z0-9_.]+)\((.*?)\)\s*"
                         r"returns\b.*?\bas\s*(\$[a-z0-9_]*\$)(.*?)\3\s*;", re.I | re.M | re.S)
    result = {}
    for match in pattern.finditer(text):
        if match[1] in result:
            raise ValueError('overloaded source is not supported: ' + match[1])
        result[match[1]] = (match[0], match[3], match[4])
    return result


def replacement(source, body):
    text, tag, old_body = source
    if text.count(tag + old_body + tag) != 1:
        raise ValueError('ambiguous function body')
    return re.sub(r'^create function', 'create or replace function',
                  text.replace(tag + old_body + tag, tag + body + tag), flags=re.I)


def produce():
    spec = importlib.util.spec_from_file_location('paid_hours_v1', ROOT / 'tool/prepare_checkout_paid_hours.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    source = functions((ROOT / 'docs/candidates/checkout_paid_hours_ledger.sql.review-only').read_text())
    source.update(functions((ROOT / 'docs/candidates/closed_day_paid_hours_scope.sql.review-only').read_text()))
    source.update(functions((ROOT / 'docs/candidates/checkout_paid_hours_api.sql.review-only').read_text()))
    source.update(functions(module.produce()))
    body_by_name = {
        'company_checkout_allowance_private.report_basis': """
 select case when checkout_shared_hours_private.uses_contract(rid) then
  jsonb_build_object('signature_contract_version',2,'work_report',shared_daily_report_private.work_basis(rid))
 else checkout_shared_hours_private.report_basis_legacy_v1(rid) end
""",
        'checkout_paid_hours_candidate_private.capture_report': """
begin
 if checkout_shared_hours_private.uses_contract(rid) then
  perform checkout_shared_hours_private.capture_report(rid,p_signature);
 else perform checkout_shared_hours_private.capture_report_legacy_v1(rid,p_signature);end if;
end
""",
        'checkout_paid_hours_candidate_private.read_hours': """
begin
 if exists(select 1 from checkout_shared_hours_private.work_protocol protocol
  join public.daily_reports r on r.id=protocol.report_id
  join public.daily_report_workers w on w.report_id=r.id and w.worker_id=wid
  where r.company_id=cid and r.report_date=p_day) then
  return checkout_shared_hours_private.read_hours(cid,wid,p_day);
 end if;
 return checkout_shared_hours_private.read_hours_legacy_v1(cid,wid,p_day);
end
""",
        'checkout_paid_hours_candidate_private.read_input': """
begin
 if checkout_shared_hours_private.uses_contract(rid) or checkout_shared_hours_private.enrollment_available(rid) then
  return checkout_shared_hours_private.read_input(rid,wid);end if;
 return checkout_shared_hours_private.read_input_legacy_v1(rid,wid);
end
""",
        'checkout_paid_hours_candidate_private.save_input': """
begin
 if checkout_shared_hours_private.uses_contract(rid) then
  return checkout_shared_hours_private.save_input(rid,wid,p_hours,p_expected_revision,p_expected_scope);end if;
 return checkout_shared_hours_private.save_input_legacy_v1(rid,wid,p_hours,p_expected_revision,p_expected_scope);
end
""",
    }
    signatures = {
        'company_checkout_allowance_private.report_basis': ('uuid', 'report_basis_legacy_v1'),
        'checkout_paid_hours_candidate_private.capture_report': ('uuid,jsonb', 'capture_report_legacy_v1'),
        'checkout_paid_hours_candidate_private.read_hours': ('uuid,uuid,date', 'read_hours_legacy_v1'),
        'checkout_paid_hours_candidate_private.read_input': ('uuid,uuid', 'read_input_legacy_v1'),
        'checkout_paid_hours_candidate_private.save_input': ('uuid,uuid,numeric,bigint,text', 'save_input_legacy_v1'),
    }
    pins = ["DO $v2_pins$ BEGIN"]
    helpers = json.loads((ROOT / 'tool/fixtures/checkout_shared_hours_v2_helpers.json').read_text())
    for helper in helpers['functions']:
        signature = helper['signature']
        digest = helper['source_md5']
        definer = 'true' if helper['security_definer'] else 'false'
        pins.append(f" IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure('{signature}') "
                    f"AND md5(p.prosrc)='{digest}' AND pg_get_userbyid(p.proowner)='postgres' "
                    f"AND p.prosecdef={definer} AND p.proconfig=ARRAY['search_path=\"\"'] "
                    f"AND p.proacl=ARRAY[makeaclitem(p.proowner,p.proowner,'EXECUTE',false)]) "
                    f"THEN RAISE EXCEPTION 'shared-hours helper differs: {signature}'; END IF;")
    clones, dispatch = [], []
    closed_name = 'checkout_paid_hours_candidate_private.read_closed_day_scope'
    closed_text, closed_tag, closed_body = source[closed_name]
    actor_gate = """if auth.uid() is null or private.account_access_allowed() is distinct from true
 or not exists(select 1 from public.company_members where company_id=cid and user_id=auth.uid())
 or not exists(select 1 from public.workers where id=wid and company_id=cid)"""
    if closed_body.count(actor_gate) != 1:
        raise ValueError('exact owner-only source clone anchor unavailable')
    closed_digest = hashlib.md5(closed_body.encode()).hexdigest()
    pins.append(f" IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure('{closed_name}(uuid,uuid,date,uuid)') "
                f"AND md5(p.prosrc)='{closed_digest}') THEN RAISE EXCEPTION 'shared-hours canonical source reader differs'; END IF;")
    pure_body = closed_body.replace(actor_gate,
        'if not exists(select 1 from public.workers where id=wid and company_id=cid)')
    closed_clone = closed_text.replace(closed_tag + closed_body + closed_tag,
                                      closed_tag + pure_body + closed_tag)
    closed_clone = closed_clone.replace(closed_name, 'checkout_shared_hours_private.read_source_scope', 1)
    clones.append(closed_clone)
    clones.append('REVOKE ALL ON FUNCTION checkout_shared_hours_private.read_source_scope(uuid,uuid,date,uuid) FROM public,anon,authenticated,service_role;')
    for name, body in body_by_name.items():
        text, _, old_body = source[name]
        argtypes, legacy_name = signatures[name]
        # Source guards are evaluated BEFORE any CREATE OR REPLACE.
        digest = hashlib.md5(old_body.encode()).hexdigest()
        pins.append(f" IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure('{name}({argtypes})') "
                    f"AND md5(p.prosrc)='{digest}' AND pg_get_userbyid(p.proowner)='postgres') "
                    f"THEN RAISE EXCEPTION 'shared-hours v1 source differs: {name}'; END IF;")
        clone_name = 'checkout_shared_hours_private.' + legacy_name
        clone = re.sub(r'^create(?: or replace)? function\s+' + re.escape(name),
                       'create function ' + clone_name, text, count=1, flags=re.I)
        clones.append(clone)
        clones.append(f'REVOKE ALL ON FUNCTION {clone_name}({argtypes}) FROM public,anon,authenticated,service_role;')
        dispatch.append(replacement(source[name], body))
    aggregate_name = 'checkout_paid_hours_candidate_private.aggregate_with_hours'
    text, tag, old = source[aggregate_name]
    anchor = "'quantity_basis','dual_signed_closed_day_ledger'"
    if old.count(anchor) != 1:
        raise ValueError('exact quantity basis anchor unavailable')
    digest = hashlib.md5(old.encode()).hexdigest()
    pins.append(f" IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure('{aggregate_name}(jsonb,jsonb)') "
                f"AND md5(p.prosrc)='{digest}') THEN RAISE EXCEPTION 'shared-hours aggregate source differs'; END IF;")
    pins.append('END $v2_pins$;')
    new = old.replace(anchor, """'quantity_basis',case when exists(select 1 from
      jsonb_array_elements(coalesce(entry->'hours_evidence','[]'::jsonb)) e
      where e#>>'{evidence,contract_version}'='2')
      then 'shared_work_report_individual_hours_annex_v2' else 'dual_signed_closed_day_ledger' end""")
    dispatch.append(replacement((text, tag, old), new))
    refresh_name = 'checkout_paid_hours_candidate_private.refresh_clock_scope'
    text, tag, old = source[refresh_name]
    anchor = "if exists(select 1 from checkout_paid_hours_candidate_private.ledger where company_id=scope.cid and worker_id=scope.wid and work_date=scope.day) then"
    if old.count(anchor) != 1:
        raise ValueError('exact clock-refresh anchor unavailable')
    digest = hashlib.md5(old.encode()).hexdigest()
    pins.insert(-1, f" IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure('{refresh_name}()') "
                   f"AND md5(p.prosrc)='{digest}') THEN RAISE EXCEPTION 'shared-hours clock refresh differs'; END IF;")
    new = old.replace(anchor, """if exists(select 1 from checkout_paid_hours_candidate_private.ledger where company_id=scope.cid and worker_id=scope.wid and work_date=scope.day)
   or exists(select 1 from checkout_shared_hours_private.ledger where company_id=scope.cid and worker_id=scope.wid and work_date=scope.day) then""")
    dispatch.append(replacement((text, tag, old), new))
    return '\n'.join(pins + clones + dispatch) + '\n'


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    pathlib.Path(args.output).write_text(produce())
