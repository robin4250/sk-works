#!/usr/bin/env python3
"""Compare confidential critical-state exports without printing identifiers."""
import argparse
import hashlib
import json
import re
from pathlib import Path

FIELDS = {'admin_identity', 'company_memberships', 'master_role_assignments', 'feature_flags',
          'schema_acl_fingerprint', 'edge_deployment_fingerprint', 'auth_provider_configuration_fingerprint'}


def unknown(value):
    if value is None or value == '' or (isinstance(value, str) and value.lower() in {'unknown', 'unverified', 'not_collected'}):
        return True
    if isinstance(value, dict):
        return not value or any(unknown(v) for v in value.values())
    if isinstance(value, list):
        return not value or any(unknown(v) for v in value)
    return False


def checked(path):
    if path.is_symlink() or path.stat().st_mode & 0o077:
        raise ValueError('Private export file required')
    data = json.loads(path.read_text())
    if data.get('schema') != 'sko-critical-state-v1' or set(data.get('sections', {})) != FIELDS:
        raise ValueError('Critical sections missing')
    for key, section in data['sections'].items():
        if not isinstance(section, dict) or section.get('status') != 'observed' or unknown(section.get('value')):
            raise ValueError('Unknown values block comparison')
        if not isinstance(section.get('evidence_sha256'), str) or not re.fullmatch('[0-9a-f]{64}', section['evidence_sha256']):
            raise ValueError('Evidence digest missing')
        value = section['value']
        def identity(row):
            return isinstance(row, dict) and all(isinstance(row.get(k), str) and row[k]
                for k in ('user_id', 'company_id', 'role'))
        if key == 'admin_identity' and not identity(value):
            raise ValueError('Administrator identifiers and role are required')
        if key == 'company_memberships' and not (isinstance(value, list) and all(identity(v) for v in value)):
            raise ValueError('Membership identifiers and roles are required')
        if key == 'master_role_assignments' and not (isinstance(value, list) and all(isinstance(v, dict)
                and isinstance(v.get('user_id'), str) and v['user_id']
                and isinstance(v.get('enabled'), bool) for v in value)):
            raise ValueError('Master assignment identifiers are required')
        if key == 'feature_flags' and not (isinstance(value, dict) and all(isinstance(v, bool) for v in value.values())):
            raise ValueError('Feature values must be observed booleans')
        if key.endswith('_fingerprint') and not (isinstance(value, str) and re.fullmatch('[0-9a-f]{64}', value)):
            raise ValueError('Observed configuration fingerprint required')
    return data


def compare(before, after):
    a, b = checked(before), checked(after)
    differences = [key for key in sorted(FIELDS)
                   if a['sections'][key]['value'] != b['sections'][key]['value']]
    return {'schema': 'sko-critical-comparison-v1', 'changed_sections': differences,
            'all_critical_values_equal': not differences,
            'baseline_sha256': hashlib.sha256(before.read_bytes()).hexdigest(),
            'restored_sha256': hashlib.sha256(after.read_bytes()).hexdigest(),
            'production_change_authorized': False,
            'limit': 'Comparison checks supplied exports only; it does not authenticate collection, verify database restore or grant approval.'}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--before', type=Path, required=True)
    p.add_argument('--after', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    try:
        result = compare(args.before, args.after)
        # Do not overwrite an older evidence result.
        with args.output.open('x') as stream:
            __import__('os').fchmod(stream.fileno(), 0o600)
            json.dump(result, stream, indent=2)
        print('Critical-state comparison saved privately. Production approval remains required.')
        return 0 if result['all_critical_values_equal'] else 2
    except (ValueError, OSError, TypeError, KeyError):
        print('Comparison BLOCKED: incomplete, unknown, invalid or unprotected evidence. No production authorization.')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
