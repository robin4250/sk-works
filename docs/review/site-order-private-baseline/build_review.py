"""Offline source review only: never connects to a database or creates an installer."""
import argparse
import hashlib
import json
import pathlib
import re

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def sha(value):
    return hashlib.sha256(value).hexdigest()


def prepare(root=ROOT, manifest=None):
    manifest = manifest or json.loads((HERE / 'manifest.json').read_text())
    sources = {}
    for name, expected in manifest['sources'].items():
        raw = (root / name).read_bytes()
        if sha(raw) != expected:
            raise ValueError('canonical source changed: ' + name)
        sources[name] = raw.decode()
    consent = sources['docs/candidates/trade_document_bound_seal_consent_20261021.sql.review-only']
    api = sources['docs/candidates/trade_document_confirmation_api_20261022.sql.review-only']
    matches = re.findall(r'create function trade_document_confirmation_api_private\.actor\(\).*?end \$\$;', api, re.S)
    if len(matches) != 1 or sha(matches[0].encode()) != manifest['actor_statement_sha256']:
        raise ValueError('actor exact statement changed')
    body = matches[0].split('as $$', 1)[1].rsplit('$$;', 1)[0]
    if hashlib.md5(body.encode()).hexdigest() != manifest['actor_body_md5']:
        raise ValueError('actor body does not match site prerequisite')
    # Keep fail-closed financial adapters verbatim; never substitute fixture permits.
    if "parent confirmation and formal counterparty adapter is not connected" not in consent:
        raise ValueError('parent denial missing')
    linked = re.search(r'create function trade_document_consent_private.linked_view_allowed\(.*?\$\$;', consent, re.S)
    if linked is None or not re.search(r'\bselect false\b', linked.group(), re.I):
        raise ValueError('linked-view denial missing')
    actor = ('-- REVIEW FRAGMENT ONLY. Not an installation or transaction bundle.\n'
             'create schema trade_document_confirmation_api_private;\n'
             'revoke all on schema trade_document_confirmation_api_private from public,anon,authenticated,service_role;\n'
             + matches[0] + '\nrevoke all on function trade_document_confirmation_api_private.actor() from public,anon,authenticated,service_role;\n')
    return {'canonical-consent.sql.review-only': consent,
            'actor-only.sql.review-only': actor}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=pathlib.Path, required=True)
    args = parser.parse_args()
    fragments = prepare()
    args.output.mkdir(parents=True, exist_ok=False)
    for name, text in fragments.items():
        (args.output / name).write_text(text)
    (args.output / 'STOP-NOT-INSTALL-READY.txt').write_text(
        'Review fragments only. No production deployment approval. Full real-helper composition and catalog gates remain open.\n')


if __name__ == '__main__':
    main()
