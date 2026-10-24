#!/usr/bin/env python3
"""Disposable CI proof for the repeated-observer installer; no hosted connection."""
import copy
import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

import prepare_company_rate_defaults_install as deployment


def main():
    container = os.environ.get('FIXTURE_CONTAINER', '')
    if os.environ.get('CI') != 'true' or not re.fullmatch('[0-9a-f]{12,64}', container):
        raise RuntimeError('dedicated disposable CI container required')
    if any(key in os.environ for key in ['SUPABASE_ACCESS_TOKEN', 'SUPABASE_DB_PASSWORD', 'SUPABASE_SERVICE_ROLE_KEY']):
        raise RuntimeError('hosted credentials are forbidden in this proof')
    root = Path.cwd()

    def sql(text):
        return subprocess.run(['docker', 'exec', '-i', container, 'psql', '-XAtq', '-U', 'postgres',
                               '-v', 'ON_ERROR_STOP=1'], input=text, text=True, capture_output=True,
                              timeout=45, check=True).stdout.strip()

    def snapshot():
        value = sql('begin read only;\n' + deployment.observer(root) +
                    "select current_setting('sko.rate_defaults_observation')::jsonb;\nrollback;\n")
        return json.loads(value)

    def rejected(text):
        try:
            sql(text)
        except subprocess.CalledProcessError:
            return
        raise AssertionError('expected transaction rejection')

    # The runtime fixture has already exercised the candidate. Remove only its
    # four functions to establish an installation baseline inside this fixture.
    sql('drop function public.read_company_rate_defaults(uuid),public.save_company_rate_defaults(uuid,jsonb,jsonb);'
        'drop function company_common_allowance_private.save_rate_defaults(uuid,jsonb,jsonb),'
        'company_common_allowance_private.read_rate_defaults(uuid);')
    production_manifest = json.loads((root / deployment.MANIFEST).read_text())
    # Uncalled stand-ins fill only the catalog paths not needed by the runtime
    # fixture. Actual trigger bodies remain installed and source-hash checked.
    for sig in production_manifest['protected_existing_routines']:
        if not re.fullmatch(r'[a-z_]+\.[a-z_]+\([a-z_, ]*\)', sig):
            raise AssertionError('unexpected fixture signature')
        if sql('select to_regprocedure(' + deployment.literal(sig) + ') is not null;') == 'f':
            sql('create function ' + sig + " returns void language plpgsql set search_path='' as $$begin return;end$$;")
    before = snapshot()
    with tempfile.TemporaryDirectory(prefix='rate-defaults-install-proof-') as directory:
        fixture_root = Path(directory)
        for name in [deployment.UNIT, deployment.OBSERVER]:
            target = fixture_root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(root / name, target)
        manifest = copy.deepcopy(production_manifest)
        # This overrides only fixture-original fingerprints, never the reviewed
        # four-function unit hash or expected new source bodies.
        manifest['protected_existing_routines'] = {
            sig: {'source_md5': value['source_md5'], 'owner': value['owner'],
                  'security_definer': value['attributes']['prosecdef'],
                  'search_path': value['attributes']['proconfig'],
                  'volatility': value['attributes']['provolatile']}
            for sig, value in before['routines'].items()}
        target = fixture_root / deployment.MANIFEST
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(manifest))
        install = deployment.prepare_install(fixture_root, before)
        sql("update public.companies set default_welfare_rate=default_welfare_rate+1 where id='10000000-0000-0000-0000-000000000001';")
        rejected(install)
        sql("update public.companies set default_welfare_rate=default_welfare_rate-1 where id='10000000-0000-0000-0000-000000000001';")
        assert snapshot() == before, 'stale guard rollback or fixture reset differed'
        rejected(install.rsplit('commit;', 1)[0] +
                 "do $$begin raise exception 'injected install failure';end$$;\ncommit;\n")
        assert snapshot() == before, 'late install failure left objects/data'
        sql('create role fixture_rate_unknown;alter default privileges grant execute on functions to fixture_rate_unknown;')
        rejected(install)
        assert snapshot() == before, 'unknown default ACL left installed functions'
        sql('alter default privileges revoke execute on functions from fixture_rate_unknown;')
        sql(install)
        after = snapshot()
        assert after['data'] == before['data'], 'function installation changed writer data'
        removal = deployment.prepare_code_removal(fixture_root, before, after)
        sql(removal)
        assert snapshot() == before, 'code removal did not restore the original target catalog'
        sql(install)
        sql("""select set_config('fixture.actor','20000000-0000-0000-0000-000000000001',false);
          do $$declare cid uuid:='10000000-0000-0000-0000-000000000001';v jsonb;begin
            v:=public.read_company_rate_defaults(cid)-'contract_version'-'company_id';
            perform public.save_company_rate_defaults(cid,v,v||jsonb_build_object('welfare_rate',(v->>'welfare_rate')::numeric+1));
          end$$;""")
        try:
            deployment.prepare_code_removal(fixture_root, before, snapshot())
        except ValueError:
            pass
        else:
            raise AssertionError('changed writer data accepted for code removal')
    print(json.dumps({'result': 'PASS isolated rate defaults bounded install',
                      'stale_rejected': True, 'late_failure_rollback': True,
                      'unknown_acl_rollback': True, 'function_only_rows_unchanged': True,
                      'unchanged_data_code_removal_exact': True,
                      'changed_data_removal_refused': True, 'production_changed': False,
                      'fixture_original_authorization': 'synthetic',
                      'not_a_financial_rollback': True}))


if __name__ == '__main__':
    main()
