"""Offline existing-prerequisite catalog guard; never queries or mutates a DB."""
import argparse
import hashlib
import json
import pathlib

HERE = pathlib.Path(__file__).resolve().parent


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def validate(snapshot, manifest):
    funcs = {f['signature']: f for f in snapshot['functions']}
    expected = {f['signature']: f for f in manifest['existing_function_contracts']}
    if set(funcs) != set(expected):
        raise ValueError('existing helper signature set changed')
    for signature, wanted in expected.items():
        actual = funcs[signature]
        attrs = actual['attrs']
        if (actual['body_md5'] != wanted['source_md5'] or
                attrs['prosecdef'] != wanted['security_definer'] or
                attrs['provolatile'] != wanted['volatility'] or
                attrs['proconfig'] != wanted['config'] or
                actual['owner'] != wanted['owner'] or actual['acl'] != wanted['acl']):
            raise ValueError('existing helper contract changed: ' + signature)
    if sorted(t['name'] for t in snapshot['relations']) != manifest['existing_relation_names']:
        raise ValueError('all nine existing relation contracts required')
    for table in snapshot['relations']:
        if not table['columns']:
            raise ValueError('existing relation missing: ' + table['name'])
    return True


def compare(before, after, manifest):
    validate(before, manifest)
    validate(after, manifest)
    differences = []
    for section, key in [('functions', 'signature'), ('relations', 'name')]:
        old = {v[key]: v for v in before[section]}
        new = {v[key]: v for v in after[section]}
        for identity in sorted(set(old) | set(new)):
            if digest(old.get(identity)) != digest(new.get(identity)):
                differences.append(section + ':' + identity)
    if digest(before['default_acls']) != digest(after['default_acls']):
        differences.append('default_acls')
    if before['server_version_num'] != after['server_version_num']:
        differences.append('server_version_num')
    if differences:
        raise ValueError('existing catalog drift; stop: ' + ', '.join(differences))
    return {'existing_prerequisites_unchanged': True,
            'full_catalog_fields_compared': True,
            'new_namespaces_after': after['new_namespace_presence'],
            'new_object_catalog_not_covered': True,
            'installation_ready': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('before', type=pathlib.Path)
    parser.add_argument('after', type=pathlib.Path)
    args = parser.parse_args()
    manifest = json.loads((HERE / 'manifest.json').read_text())
    print(json.dumps(compare(json.loads(args.before.read_text()), json.loads(args.after.read_text()), manifest)))


if __name__ == '__main__':
    main()
