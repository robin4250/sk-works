"""Offline metadata qualification only. Never emits SQL or grants approval."""
import copy
import hashlib
import json
import re

INSTALLER_SHA256 = 'b45d269b22e58a6e9a4750d6398a6139ee854c1c820ed376d7e3c8a87ae49e95'
INSTALLER_PATH = 'docs/candidates/app_distribution_off_install_20261020.sql.review-only'
SOURCE_COMMIT = '48d345ddd52f5cca0166c2d6545a07ecb08fe8d4'
PROFILES = [{'signature': 'private.app_distribution_dispatch(text,jsonb)',
  'exists': False,
  'owner': None,
  'language': None,
  'security_definer': None,
  'strict': None,
  'leakproof': None,
  'returns_set': None,
  'volatility': None,
  'parallel': None,
  'kind': None,
  'settings': None,
  'arg_types': None,
  'arg_names': None,
  'arg_defaults': None,
  'result_type': None,
  'body_md5': None,
  'definition_md5': None,
  'acl': None},
 {'signature': 'private.app_referral_dispatch(text,jsonb)',
  'exists': True,
  'owner': 'postgres',
  'language': 'plpgsql',
  'security_definer': True,
  'strict': False,
  'leakproof': False,
  'returns_set': False,
  'volatility': 'v',
  'parallel': 'u',
  'kind': 'f',
  'settings': ['search_path=""'],
  'arg_types': 'text, jsonb',
  'arg_names': ['p_action', 'p_args'],
  'arg_defaults': "'{}'::jsonb",
  'result_type': 'jsonb',
  'body_md5': '3ccced6e2d9a82d715e07c6b3f25b490',
  'definition_md5': '4de25c5e1a41ecf2338c573d6fb49f5f',
  'acl': [{'grantee': 'postgres',
           'grantor': 'postgres',
           'privilege': 'EXECUTE',
           'grantable': False},
          {'grantee': 'authenticated',
           'grantor': 'postgres',
           'privilege': 'EXECUTE',
           'grantable': False}]},
 {'signature': 'public.app_distribution_prepare(text,text,text,text)',
  'exists': False,
  'owner': None,
  'language': None,
  'security_definer': None,
  'strict': None,
  'leakproof': None,
  'returns_set': None,
  'volatility': None,
  'parallel': None,
  'kind': None,
  'settings': None,
  'arg_types': None,
  'arg_names': None,
  'arg_defaults': None,
  'result_type': None,
  'body_md5': None,
  'definition_md5': None,
  'acl': None},
 {'signature': 'public.app_distribution_save_links(text,text,text)',
  'exists': False,
  'owner': None,
  'language': None,
  'security_definer': None,
  'strict': None,
  'leakproof': None,
  'returns_set': None,
  'volatility': None,
  'parallel': None,
  'kind': None,
  'settings': None,
  'arg_types': None,
  'arg_names': None,
  'arg_defaults': None,
  'result_type': None,
  'body_md5': None,
  'definition_md5': None,
  'acl': None},
 {'signature': 'public.app_distribution_snapshot(boolean)',
  'exists': False,
  'owner': None,
  'language': None,
  'security_definer': None,
  'strict': None,
  'leakproof': None,
  'returns_set': None,
  'volatility': None,
  'parallel': None,
  'kind': None,
  'settings': None,
  'arg_types': None,
  'arg_names': None,
  'arg_defaults': None,
  'result_type': None,
  'body_md5': None,
  'definition_md5': None,
  'acl': None},
 {'signature': 'public.app_referral_composer_opened(uuid)',
  'exists': True,
  'owner': 'postgres',
  'language': 'sql',
  'security_definer': False,
  'strict': False,
  'leakproof': False,
  'returns_set': False,
  'volatility': 'v',
  'parallel': 'u',
  'kind': 'f',
  'settings': ['search_path=""'],
  'arg_types': 'uuid',
  'arg_names': ['p_invitation_id'],
  'arg_defaults': None,
  'result_type': 'jsonb',
  'body_md5': '54a0542403ccff7bc284570328fd60ae',
  'definition_md5': 'bdad6760c030bd67a3ac980b553f57e6',
  'acl': [{'grantee': 'postgres',
           'grantor': 'postgres',
           'privilege': 'EXECUTE',
           'grantable': False},
          {'grantee': 'authenticated',
           'grantor': 'postgres',
           'privilege': 'EXECUTE',
           'grantable': False},
          {'grantee': 'service_role',
           'grantor': 'postgres',
           'privilege': 'EXECUTE',
           'grantable': False}]},
 {'signature': 'public.app_referral_master_snapshot()',
  'exists': True,
  'owner': 'postgres',
  'language': 'sql',
  'security_definer': False,
  'strict': False,
  'leakproof': False,
  'returns_set': False,
  'volatility': 'v',
  'parallel': 'u',
  'kind': 'f',
  'settings': ['search_path=""'],
  'arg_types': '',
  'arg_names': [],
  'arg_defaults': None,
  'result_type': 'jsonb',
  'body_md5': '1b482366e87e99f6ae6188dffbdd0e86',
  'definition_md5': '7c90c91a868497e41eab4f24bd8228aa',
  'acl': [{'grantee': 'postgres',
           'grantor': 'postgres',
           'privilege': 'EXECUTE',
           'grantable': False},
          {'grantee': 'authenticated',
           'grantor': 'postgres',
           'privilege': 'EXECUTE',
           'grantable': False},
          {'grantee': 'service_role',
           'grantor': 'postgres',
           'privilege': 'EXECUTE',
           'grantable': False}]},
 {'signature': 'public.app_referral_prepare(text,text,text)',
  'exists': True,
  'owner': 'postgres',
  'language': 'sql',
  'security_definer': False,
  'strict': False,
  'leakproof': False,
  'returns_set': False,
  'volatility': 'v',
  'parallel': 'u',
  'kind': 'f',
  'settings': ['search_path=""'],
  'arg_types': 'text, text, text',
  'arg_names': ['p_name', 'p_phone', 'p_source'],
  'arg_defaults': "'app_invite'::text",
  'result_type': 'jsonb',
  'body_md5': 'd166f04a952b1ef6433df8b0a08d8950',
  'definition_md5': '034ad1481eabc6472dad98524cce384e',
  'acl': [{'grantee': 'postgres',
           'grantor': 'postgres',
           'privilege': 'EXECUTE',
           'grantable': False},
          {'grantee': 'authenticated',
           'grantor': 'postgres',
           'privilege': 'EXECUTE',
           'grantable': False},
          {'grantee': 'service_role',
           'grantor': 'postgres',
           'privilege': 'EXECUTE',
           'grantable': False}]},
 {'signature': 'public.app_referral_save_flags(boolean,boolean,boolean)',
  'exists': False,
  'owner': None,
  'language': None,
  'security_definer': None,
  'strict': None,
  'leakproof': None,
  'returns_set': None,
  'volatility': None,
  'parallel': None,
  'kind': None,
  'settings': None,
  'arg_types': None,
  'arg_names': None,
  'arg_defaults': None,
  'result_type': None,
  'body_md5': None,
  'definition_md5': None,
  'acl': None},
 {'signature': 'public.app_referral_save_settings(boolean,boolean,boolean,text)',
  'exists': True,
  'owner': 'postgres',
  'language': 'sql',
  'security_definer': False,
  'strict': False,
  'leakproof': False,
  'returns_set': False,
  'volatility': 'v',
  'parallel': 'u',
  'kind': 'f',
  'settings': ['search_path=""'],
  'arg_types': 'boolean, boolean, boolean, text',
  'arg_names': ['p_enabled', 'p_public_enabled', 'p_notify_master', 'p_distribution_url'],
  'arg_defaults': None,
  'result_type': 'jsonb',
  'body_md5': '2ea1f02bc5bbb42f60b7d263fd4fa12a',
  'definition_md5': '63ae00fa69438e33c1814ed63e143194',
  'acl': [{'grantee': 'postgres',
           'grantor': 'postgres',
           'privilege': 'EXECUTE',
           'grantable': False},
          {'grantee': 'authenticated',
           'grantor': 'postgres',
           'privilege': 'EXECUTE',
           'grantable': False},
          {'grantee': 'service_role',
           'grantor': 'postgres',
           'privilege': 'EXECUTE',
           'grantable': False}]},
 {'signature': 'public.app_referral_snapshot()',
  'exists': True,
  'owner': 'postgres',
  'language': 'sql',
  'security_definer': False,
  'strict': False,
  'leakproof': False,
  'returns_set': False,
  'volatility': 'v',
  'parallel': 'u',
  'kind': 'f',
  'settings': ['search_path=""'],
  'arg_types': '',
  'arg_names': [],
  'arg_defaults': None,
  'result_type': 'jsonb',
  'body_md5': 'a46a289917abebcff59c2e950ce6e2f7',
  'definition_md5': '298afc496a66e20cb5090964a2c5d355',
  'acl': [{'grantee': 'postgres',
           'grantor': 'postgres',
           'privilege': 'EXECUTE',
           'grantable': False},
          {'grantee': 'authenticated',
           'grantor': 'postgres',
           'privilege': 'EXECUTE',
           'grantable': False},
          {'grantee': 'service_role',
           'grantor': 'postgres',
           'privilege': 'EXECUTE',
           'grantable': False}]},
 {'signature': 'public.initial_registration_distribution_settings()',
  'exists': True,
  'owner': 'postgres',
  'language': 'plpgsql',
  'security_definer': True,
  'strict': False,
  'leakproof': False,
  'returns_set': False,
  'volatility': 's',
  'parallel': 'u',
  'kind': 'f',
  'settings': ['search_path=""'],
  'arg_types': '',
  'arg_names': [],
  'arg_defaults': None,
  'result_type': 'jsonb',
  'body_md5': '787c9fcc6cdd7ed61dfc2e1a8c78ab93',
  'definition_md5': 'ee284c57c7545d53c4294f3639332dad',
  'acl': [{'grantee': 'postgres',
           'grantor': 'postgres',
           'privilege': 'EXECUTE',
           'grantable': False},
          {'grantee': 'authenticated',
           'grantor': 'postgres',
           'privilege': 'EXECUTE',
           'grantable': False},
          {'grantee': 'service_role',
           'grantor': 'postgres',
           'privilege': 'EXECUTE',
           'grantable': False}]},
 {'signature': 'public.save_initial_registration_distribution_settings(text)',
  'exists': True,
  'owner': 'postgres',
  'language': 'plpgsql',
  'security_definer': True,
  'strict': False,
  'leakproof': False,
  'returns_set': False,
  'volatility': 'v',
  'parallel': 'u',
  'kind': 'f',
  'settings': ['search_path=""'],
  'arg_types': 'text',
  'arg_names': ['p_testflight_url'],
  'arg_defaults': None,
  'result_type': 'void',
  'body_md5': '6a5059435727bda97f32964d88e7ac28',
  'definition_md5': 'b7cbf878bc62fc874b5554de24112970',
  'acl': [{'grantee': 'postgres',
           'grantor': 'postgres',
           'privilege': 'EXECUTE',
           'grantable': False},
          {'grantee': 'authenticated',
           'grantor': 'postgres',
           'privilege': 'EXECUTE',
           'grantable': False},
          {'grantee': 'service_role',
           'grantor': 'postgres',
           'privilege': 'EXECUTE',
           'grantable': False}]}]
PREDICATES = {'settings_singleton_exact_one', 'invitations_off', 'public_off', 'legacy_url_empty'}
OID_FIELDS = {'oid', 'schema_oid', 'owner_oid'}
ACL_OIDS = {'grantee_oid', 'grantor_oid'}

class Rejected(ValueError):
    """Input cannot support even an offline review capsule."""

def require(condition, reason):
    if not condition:
        raise Rejected(reason)

def exact_keys(value, keys, reason):
    require(type(value) is dict and set(value) == set(keys), reason)

def positive_oid(value):
    return type(value) is int and 0 < value <= 4294967295

def normalized(row):
    result = {k: v for k, v in row.items() if k not in OID_FIELDS}
    if result['acl'] is not None:
        result['acl'] = [{k: v for k, v in a.items() if k not in ACL_OIDS} for a in result['acl']]
        result['acl'].sort(key=lambda a: (a['grantee'], a['grantor']))
    return result

def validate_catalog(rows):
    require(type(rows) is list and len(rows) == len(PROFILES), 'catalog cardinality')
    indexed = {}
    oids = set()
    for row in rows:
        exact_keys(row, set(PROFILES[0]) | OID_FIELDS, 'catalog fields')
        signature = row['signature']
        require(type(signature) is str and signature not in indexed, 'catalog duplicate/signature')
        indexed[signature] = row
        if row['exists'] is True:
            require(all(positive_oid(row[k]) for k in OID_FIELDS), 'catalog OID')
            require(row['oid'] not in oids, 'catalog duplicate OID')
            oids.add(row['oid'])
            require(type(row['acl']) is list, 'catalog ACL')
            for acl in row['acl']:
                exact_keys(acl, {'grantee', 'grantor', 'privilege', 'grantable'} | ACL_OIDS, 'ACL fields')
                require(all(positive_oid(acl[k]) for k in ACL_OIDS), 'ACL OID')
                require(all(type(acl[k]) is str for k in ('grantee', 'grantor', 'privilege')), 'ACL name type')
                require(type(acl['grantable']) is bool, 'ACL grant option type')
                require(acl['grantor_oid'] == row['owner_oid'], 'ACL grantor binding')
                if acl['grantee'] == row['owner']:
                    require(acl['grantee_oid'] == row['owner_oid'], 'ACL owner binding')
        else:
            require(row['exists'] is False and all(row[k] is None for k in OID_FIELDS), 'absence/OID')
    require(set(indexed) == {p['signature'] for p in PROFILES}, 'catalog signatures')
    for profile in PROFILES:
        actual = normalized(indexed[profile['signature']])
        expected = copy.deepcopy(profile)
        if expected['acl'] is not None:
            expected['acl'].sort(key=lambda a: (a['grantee'], a['grantor']))
        # JSON canonicalization also distinguishes booleans from 0/1.
        require(json.dumps(actual, sort_keys=True) == json.dumps(expected, sort_keys=True), 'source/ACL/attribute drift')
    return indexed

def qualify(installer, evidence):
    require(type(installer) is bytes and hashlib.sha256(installer).hexdigest() == INSTALLER_SHA256, 'immutable installer hash')
    exact_keys(evidence, {'baseline', 'current', 'overloads', 'settings', 'preservation_reference'}, 'evidence fields')
    baseline = validate_catalog(evidence['baseline'])
    current = validate_catalog(evidence['current'])
    require(baseline == current, 'baseline/current identity drift')
    # Full signatures for every same-name overload must be supplied, including absent names.
    require(type(evidence['overloads']) is list and all(type(s) is str for s in evidence['overloads']), 'overload types')
    expected = sorted(p['signature'] for p in PROFILES if p['exists'])
    require(sorted(evidence['overloads']) == expected, 'unknown/missing/duplicate overload')
    exact_keys(evidence['settings'], PREDICATES, 'settings fields')
    require(all(type(v) is bool and v is True for v in evidence['settings'].values()), 'OFF/empty precondition not satisfied')
    ref = evidence['preservation_reference']
    exact_keys(ref, {'sha256', 'scope', 'verified'}, 'preservation reference fields')
    require(type(ref['sha256']) is str and re.fullmatch('[0-9a-f]{64}', ref['sha256']) is not None, 'preservation reference hash')
    require(ref['scope'] == 'private-before-post-settings-history-dependencies', 'preservation reference scope')
    require(ref['verified'] is False, 'external preservation contents are not verified by this tool')
    return {
        'format': 'distribution-off-review-capsule-v1',
        'deployable': False, 'approval': False, 'execution': None, 'sql': None,
        'source_commit': SOURCE_COMMIT,
        'installer': {'path': INSTALLER_PATH, 'sha256': INSTALLER_SHA256},
        'before': copy.deepcopy(evidence),
        'post_allowlist': {
            'replace_body_only': ['private.app_referral_dispatch(text,jsonb)'],
            'create_functions': [p['signature'] for p in PROFILES if not p['exists']],
            'create_tables': ['private.app_distribution_links', 'private.app_distribution_invitation_channels'],
            'preserve': 'all other definitions, owners, ACLs, settings, histories and company URLs',
        },
        'blocked': ['private preservation anchor contents unverified', 'full dependency closure and atomic before/post guard not bound', 'freshness, project identity, namespace OID and non-owner role OID mapping require independent private verification', 'production approval absent', 'no execution path exists'],
    }
