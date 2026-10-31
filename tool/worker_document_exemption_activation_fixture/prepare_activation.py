"""Generate non-runnable review capsules from a root-captured catalog receipt.
Never connects to any database. No production application or employee exemption.
"""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
QUERY = (ROOT / 'read-catalog.sql').read_text()
QUERY = QUERY[QUERY.index('select jsonb_build_object('):]
EXPR = QUERY.removesuffix(' as snapshot;\n').removeprefix('select ')

def build(snapshot, target, approved=False):
    previous = not target
    state = snapshot['module_state']
    if state != dict(enabled=previous, settings_count=1, decision_count=0, event_count=0):
        raise ValueError('Only an exact unused module state is accepted. After-use pause needs a fresh reviewed capsule.')
    if any(not value['exists'] for value in snapshot['functions'].values()):
        raise ValueError('Missing function')
    if any(not value['exists'] for value in snapshot['relations'].values()):
        raise ValueError('Missing relation')
    expected = json.dumps(snapshot, ensure_ascii=False, separators=(',', ':'))
    if '$expected$' in expected:
        raise ValueError('Unsafe JSON SQL delimiter')
    action = 'ACTIVATE_GLOBAL_EXEMPTION_MANAGEMENT' if target else 'PAUSE_GLOBAL_EXEMPTION_MANAGEMENT_UNUSED'
    return f'''-- PRIVATE REVIEW ONLY. Approval is absent; default gate always aborts.
-- No company/self activation API. Scope is GLOBAL, not one employee/company.
-- Only singleton enabled changes. No DDL/ACL/grants/decisions/events/documents.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
do $activation$
declare
 approved boolean := {str(approved).lower()};
 expected jsonb := $expected${expected}$expected$::jsonb;
 observed jsonb;
 changed integer;
begin
 if not approved then
  raise exception 'STOP: explicit approval for {action} and independent review are required' using errcode='55000';
 end if;
 lock table private.worker_document_exemption_settings in access exclusive mode;
 lock table private.worker_document_exemptions,private.worker_document_exemption_events in share mode;
 select {EXPR} into observed;
 if observed is distinct from expected then
  raise exception 'Exemption catalog or unused module state changed; inspect, do not replace' using errcode='55000';
 end if;
 update private.worker_document_exemption_settings
  set enabled={str(target).lower()} where singleton and enabled={str(previous).lower()};
 get diagnostics changed = row_count;
 if changed <> 1 then
  raise exception 'Exemption setting CAS failed' using errcode='55000';
 end if;
 select {EXPR} into observed;
 if (observed - 'module_state') is distinct from (expected - 'module_state')
   or observed->'module_state' is distinct from
      jsonb_build_object('settings_count',1,'enabled',{str(target).lower()},'decision_count',0,'event_count',0) then
  raise exception 'Exemption activation after-state mismatch' using errcode='55000';
 end if;
 raise notice 'Exemption % setting changed; transaction not committed until COMMIT succeeds', '{action}';
end $activation$;
select jsonb_build_object('action','{action}','transaction_id',txid_current(),
 'checked_at',clock_timestamp(),'enabled',enabled,
 'decision_count',(select count(*) from private.worker_document_exemptions),
 'event_count',(select count(*) from private.worker_document_exemption_events)) as application_receipt
from private.worker_document_exemption_settings where singleton;
commit;
'''

def main():
    original = json.loads((ROOT / 'snapshot.normalized.private.json').read_text())
    (ROOT / 'activate-unused.sql.review-only').write_text(build(original, True))
    unused_on = json.loads(json.dumps(original))
    unused_on['module_state']['enabled'] = True
    (ROOT / 'pause-unused.sql.review-only').write_text(build(unused_on, False))
    manifest = {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
                for name in ['snapshot.normalized.private.json', 'read-catalog.sql',
                             'activate-unused.sql.review-only', 'pause-unused.sql.review-only']}
    (ROOT / 'capsule-manifest.private.json').write_text(json.dumps({
        'approval_received': False, 'production_applied': False,
        'scope': 'GLOBAL management switch; no individual decision',
        'sources': manifest,
    }, indent=2) + '\n')

if __name__ == '__main__':
    main()
