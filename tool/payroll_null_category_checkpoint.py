#!/usr/bin/env python3
"""Generate review-only definition guards; never connects to or executes SQL."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re

SIGNATURE = 'private.refresh_automatic_payroll_internal(uuid,uuid,date)'
OLD = 'category:=a.work_category;'
NEW = "category:=coalesce(a.work_category,'day');"
EXPECTED_MD5 = '2c5230eea880fe8cddbe60bc6c4c0782'
META = ('oid', 'identity_arguments', 'owner', 'acl', 'proconfig', 'prosecdef', 'provolatile', 'proparallel', 'proisstrict', 'proleakproof', 'language', 'result_type')


def digest(text):
    return hashlib.sha256(text.encode()).hexdigest()


def literal(value):
    return "'" + value.replace("'", "''") + "'"


def body(definition):
    match = re.search(r'\bAS\s+(\$[A-Za-z_0-9]*\$)([\s\S]*)\1\s*;?\s*$', definition)
    if not match:
        raise ValueError('unsupported complete function definition')
    return match.group(2)


def validate(checkpoint, triggers, events=None):
    if checkpoint.get('checkpoint_schema') != 1 or checkpoint.get('signature') != SIGNATURE:
        raise ValueError('wrong checkpoint schema or signature')
    definition = checkpoint['definition']
    if definition.count(OLD) != 1 or NEW in definition:
        raise ValueError('exactly one original category assignment required')
    if digest(definition) != checkpoint['definition_sha256']:
        raise ValueError('definition digest mismatch')
    if hashlib.md5(body(definition).encode()).hexdigest() != checkpoint['source_md5'] or checkpoint['source_md5'] != EXPECTED_MD5:
        raise ValueError('unexpected source body')
    if checkpoint['owner'] != 'postgres' or checkpoint['acl'] != '{postgres=X/postgres}' or checkpoint['proconfig'] != ['search_path=""'] or checkpoint['prosecdef'] is not True:
        raise ValueError('unexpected privilege checkpoint')
    for key in META:
        if key not in checkpoint:
            raise ValueError('missing metadata')
    if not str(checkpoint['oid']).isdigit() or not triggers:
        raise ValueError('missing function OID or triggers')
    keys = {'oid','tgname','tgenabled','definition','function_schema','function_name','function_source_md5'}
    for trigger in triggers:
        if set(trigger) != keys or not str(trigger['oid']).isdigit() or not re.fullmatch('[0-9a-f]{32}', trigger['function_source_md5']):
            raise ValueError('invalid trigger checkpoint')
    if events is not None:
        event_keys = {'evtname','evtevent','evtenabled','function_schema','function_name','source_md5'}
        if not isinstance(events, list) or any(set(e) != event_keys or not all(isinstance(v,str) for v in e.values()) or not re.fullmatch('[0-9a-f]{32}',e['source_md5']) for e in events) or len({e['evtname'] for e in events}) != len(events):
            raise ValueError('invalid event trigger checkpoint')
    if len({str(t['oid']) for t in triggers}) != len(triggers):
        raise ValueError('duplicate trigger OID')


def guard(checkpoint, triggers, definition, label, events=None):
    metadata = {k: checkpoint[k] for k in META}
    metadata['oid'] = str(metadata['oid'])
    metadata_json = literal(json.dumps(metadata, ensure_ascii=True, sort_keys=True))
    trigger_json = literal(json.dumps(sorted(triggers, key=lambda t: int(t['oid'])), ensure_ascii=True, sort_keys=True))
    event_guard = ''
    if events is not None:
        event_json = literal(json.dumps(sorted(events,key=lambda e:e['evtname']),ensure_ascii=True,sort_keys=True))
        event_guard = f"""SELECT coalesce(jsonb_agg(jsonb_build_object('evtname',e.evtname,'evtevent',e.evtevent,
 'evtenabled',e.evtenabled,'function_schema',n.nspname,'function_name',p.proname,
 'source_md5',md5(p.prosrc)) ORDER BY e.evtname),'[]'::jsonb) INTO actual_events
 FROM pg_event_trigger e JOIN pg_proc p ON p.oid=e.evtfoid JOIN pg_namespace n ON n.oid=p.pronamespace;
 IF actual_events IS DISTINCT FROM {event_json}::jsonb THEN
 RAISE EXCEPTION 'payroll event trigger checkpoint mismatch' USING ERRCODE='55000'; END IF;
"""
    # Same exact-before/after strategy as manual_linker_deployment_checkpoint.
    return f'''DO $checkpoint_guard$
DECLARE actual jsonb; current_definition text; actual_triggers jsonb; actual_events jsonb;
BEGIN
 SELECT jsonb_build_object('oid',p.oid::text,'identity_arguments',pg_get_function_identity_arguments(p.oid),
 'owner',pg_get_userbyid(p.proowner),'acl',p.proacl::text,'proconfig',to_jsonb(p.proconfig),
 'prosecdef',p.prosecdef,'provolatile',p.provolatile,'proparallel',p.proparallel,
 'proisstrict',p.proisstrict,'proleakproof',p.proleakproof,'language',l.lanname,
 'result_type',pg_get_function_result(p.oid)),pg_get_functiondef(p.oid)
 INTO actual,current_definition FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang
 WHERE p.oid=to_regprocedure({literal(SIGNATURE)});
 IF actual IS DISTINCT FROM {metadata_json}::jsonb
 OR current_definition IS DISTINCT FROM {literal(definition)} THEN
 RAISE EXCEPTION 'payroll code checkpoint {label} mismatch' USING ERRCODE='55000'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('oid',t.oid::text,'tgname',t.tgname,
 'tgenabled',t.tgenabled,'definition',pg_get_triggerdef(t.oid,true),'function_schema',n.nspname,
 'function_name',p.proname,'function_source_md5',md5(p.prosrc)) ORDER BY t.oid),'[]'::jsonb)
 INTO actual_triggers FROM pg_trigger t JOIN pg_proc p ON p.oid=t.tgfoid
 JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE t.tgrelid='public.payroll_statements'::regclass AND NOT t.tgisinternal;
 IF actual_triggers IS DISTINCT FROM {trigger_json}::jsonb THEN
 RAISE EXCEPTION 'payroll trigger checkpoint mismatch' USING ERRCODE='55000'; END IF;
{event_guard}END $checkpoint_guard$;
'''


def generate(checkpoint, triggers, events=None):
    validate(checkpoint, triggers, events)
    original = checkpoint['definition']
    forward = original.replace(OLD, NEW)
    header = "-- REVIEW ONLY: no automatic execution. Definition rollback only; no payroll-row restoration.\nBEGIN;\nSET LOCAL lock_timeout='5s';\nSET LOCAL statement_timeout='20s';\n"
    def artifact(before, after, label):
        return header + guard(checkpoint, triggers, before, label+' before', events) + after.rstrip().rstrip(';') + ';\n' + guard(checkpoint, triggers, after, label+' after', events) + 'COMMIT;\n'
    outputs = {'guarded_forward.sql.review-only': artifact(original, forward, 'forward'), 'guarded_restore.sql.review-only': artifact(forward, original, 'restore')}
    manifest = {'schema_version':1,'scope':'one private function definition; no automatic recalculation','signature':SIGNATURE,'production_change_authorized':False,'code_rollback_only':True,'original_definition_sha256':digest(original),'forward_definition_sha256':digest(forward),'original_source_md5':checkpoint['source_md5'],'forward_source_md5':hashlib.md5(body(forward).encode()).hexdigest(),'trigger_count':len(triggers),'event_trigger_checkpoint_checked':events is not None,'event_trigger_count':len(events) if events is not None else None,'artifact_sha256':{k:digest(v) for k,v in outputs.items()}}
    return outputs, manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--checkpoint', type=Path, required=True)
    parser.add_argument('--triggers', type=Path, required=True)
    parser.add_argument('--event-triggers', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    for source in (args.checkpoint, args.triggers, *([args.event_triggers] if args.event_triggers else [])):
        if source.is_symlink() or not source.is_file() or source.stat().st_size > 1024*1024:
            raise ValueError('regular bounded checkpoint file required')
    parent = args.output.parent.resolve(strict=True)
    if args.output.exists() or args.output.is_symlink() or any((p/'.git').is_file() or (p/'.git'/'HEAD').is_file() for p in (parent,*parent.parents)):
        raise ValueError('new private output outside git required')
    outputs, manifest = generate(json.loads(args.checkpoint.read_text()), json.loads(args.triggers.read_text()), json.loads(args.event_triggers.read_text()) if args.event_triggers else None)
    os.umask(0o077)
    args.output.mkdir(mode=0o700)
    for name, content in outputs.items():
        (args.output/name).write_text(content)
    (args.output/'public_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print('Review-only artifacts generated. No database connection or execution. Production approval remains false.')


if __name__ == '__main__':
    main()
