"""Compose fixed reviewed HTTP source and private Wasm files. Never deploy."""
import argparse
import hashlib
import json
import os
import pathlib

P = pathlib.Path(__file__).resolve().parent
FUNCTION = pathlib.Path('supabase/functions/site-order-workflow')
GENERATED = ('main.wasm', 'main.mjs', 'main.support.js', 'runtime.mjs')


def checked_file(root, relative):
    path = root / relative
    if path.is_symlink() or not path.is_file() or not path.resolve().is_relative_to(root):
        raise ValueError('fixed_private_source_required')
    for parent in path.parents:
        if parent == root:
            break
        if parent.is_symlink():
            raise ValueError('fixed_private_source_required')
    return path.read_bytes()


def stage(source, output):
    os.umask(0o077)
    source = source.resolve(strict=True)
    if (output.exists() or output.is_symlink() or not output.is_absolute()
            or any(parent.is_symlink() for parent in output.parents)):
        raise ValueError('new_absolute_private_destination_required')
    pins = json.loads((P / 'workflow_source_pins.json').read_text())
    receipt = json.loads((P / 'build/build-receipt.json').read_text())
    if receipt != json.loads((P / 'build-proof.json').read_text()):
        raise ValueError('reviewed_build_receipt_changed')
    pending = {}
    for name, expected in pins['files'].items():
        data = checked_file(source, name)
        if hashlib.sha256(data).hexdigest() != expected:
            raise ValueError('reviewed_workflow_source_changed')
        pending[name] = data
    for name in GENERATED:
        data = checked_file(P / 'build', name)
        pin = receipt['outputs'][name]
        if len(data) != pin['bytes'] or hashlib.sha256(data).hexdigest() != pin['sha256']:
            raise ValueError('compiled_artifact_changed')
        pending[str(FUNCTION / '_canonical' / name)] = data
    adapter = checked_file(P, 'edge_adapter.mjs.in')
    if hashlib.sha256(adapter).hexdigest() != pins['adapter_sha256']:
        raise ValueError('reviewed_adapter_changed')
    pending[str(FUNCTION / '_canonical/edge_adapter.mjs')] = adapter
    total = sum(map(len, pending.values()))
    if total >= 20_000_000:
        raise ValueError('static_and_source_budget_exceeded')
    # Validate everything before creating any destination. Never copy config,
    # .env, credentials, node_modules, previous releases, or customer originals.
    output.mkdir(mode=0o700, parents=True)
    files = {}
    for name, data in pending.items():
        target = output / name
        target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        target.write_bytes(data)
        target.chmod(0o600)
        files[name] = {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
    result = {'source_commit': pins['source_commit'], 'wasm_adapter_commit': pins['wasm_adapter_commit'],
              'files': files, 'static_and_source_bytes': total,
              'complete_cli_bundle_measured': False, 'configuration_copied': False,
              'production_changed': False, 'deployed': False}
    (output / 'private-composition-manifest.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'staged_files': len(files), 'static_and_source_bytes': total,
                      'complete_cli_bundle_measured': False, 'production_changed': False, 'deployed': False}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root', type=pathlib.Path, required=True)
    parser.add_argument('--output', type=pathlib.Path, required=True)
    args = parser.parse_args()
    stage(args.source_root, args.output)
