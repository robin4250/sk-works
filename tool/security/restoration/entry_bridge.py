#!/usr/bin/env python3
"""Operator-only adapter; secret entry stays on the operator terminal."""
import getpass
import hashlib
import importlib.util
from pathlib import Path
import sys


def bind_entry(module, prompt=getpass.getpass, interactive=None):
    original = module.parse_plan

    def parse(text):
        # Validate the complete original plan before asking for a secret.
        values = original(text)
        if not (sys.stdin.isatty() if interactive is None else interactive):
            raise ValueError('interactive terminal required')
        secret = prompt('Supabase DB password (hidden; not SKO password): ')
        if not secret or '\x00' in secret or '\n' in secret or '\r' in secret:
            raise ValueError('invalid secret input')
        values['PGUSER'] = ('postgres' if values['PGHOST'] ==
                            'db.' + module.PROJECT + '.supabase.co'
                            else 'postgres.' + module.PROJECT)
        values['PGPASSWORD'] = secret
        return values

    module.parse_plan = parse


def load_collector(path):
    if hashlib.sha256(path.read_bytes()).hexdigest() != '7cdb772f6844db962eafb93f4ac44a9e4629a1edf4b79fc6659aeb3b45b29b81':
        raise ValueError('reviewed collection source mismatch')
    spec = importlib.util.spec_from_file_location('_local_entry_collection', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    # Verify before importing any local collection code or requesting a secret.
    module = load_collector(Path(__file__).with_name('collect_private_capsule.py'))
    bind_entry(module)
    return module.main()


if __name__ == '__main__':
    raise SystemExit(main())
