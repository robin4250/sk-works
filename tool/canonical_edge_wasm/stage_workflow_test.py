"""Exercise only the new composition boundary against actual compiled files."""
import contextlib
import argparse
import hashlib
import importlib.util
import io
import json
import pathlib
import shutil
import tempfile

P = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('stage_workflow', P / 'stage_workflow.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source-root', type=pathlib.Path, default=P.parents[1])
source = parser.parse_args().source_root.resolve(strict=True)
pins = json.loads((P / 'workflow_source_pins.json').read_text())

with tempfile.TemporaryDirectory(prefix='sko-workflow-composition-') as temp:
    root = pathlib.Path(temp)
    output = root / 'private'
    with contextlib.redirect_stdout(io.StringIO()):
        module.stage(source, output)
    manifest = json.loads((output / 'private-composition-manifest.json').read_text())
    assert len(manifest['files']) == 10
    assert manifest['configuration_copied'] is False and manifest['deployed'] is False
    assert manifest['complete_cli_bundle_measured'] is False
    actual = {str(p.relative_to(output)) for p in output.rglob('*') if p.is_file()}
    assert actual == set(manifest['files']) | {'private-composition-manifest.json'}
    for name, pin in manifest['files'].items():
        data = (output / name).read_bytes()
        assert len(data) == pin['bytes'] and hashlib.sha256(data).hexdigest() == pin['sha256']
        assert (output / name).stat().st_mode & 0o077 == 0
    original = (output / 'private-composition-manifest.json').read_bytes()
    try:
        module.stage(source, output)
        raise AssertionError('existing destination overwritten')
    except ValueError as error:
        assert str(error) == 'new_absolute_private_destination_required'
    assert original == (output / 'private-composition-manifest.json').read_bytes()
    copied = root / 'source'
    for name in pins['files']:
        target = copied / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source / name, target)
    first = next(iter(pins['files']))
    (copied / first).write_text('changed')
    blocked = root / 'blocked'
    try:
        module.stage(copied, blocked)
        raise AssertionError('source drift accepted')
    except ValueError as error:
        assert str(error) == 'reviewed_workflow_source_changed'
    assert not blocked.exists()
    (copied / first).unlink()
    (copied / first).symlink_to(source / first)
    try:
        module.stage(copied, blocked)
        raise AssertionError('symlink source accepted')
    except ValueError as error:
        assert str(error) == 'fixed_private_source_required'
    assert not blocked.exists()
    alias = root / 'alias'
    alias.symlink_to(root, target_is_directory=True)
    try:
        module.stage(source, alias / 'not-created')
        raise AssertionError('symlink output parent accepted')
    except ValueError as error:
        assert str(error) == 'new_absolute_private_destination_required'
    assert not (root / 'not-created').exists()
    fake = root / 'changed-receipt'
    (fake / 'build').mkdir(parents=True)
    for name in ('workflow_source_pins.json', 'build-proof.json'):
        shutil.copyfile(P / name, fake / name)
    altered = json.loads((P / 'build/build-receipt.json').read_text())
    altered['outputs']['main.wasm']['sha256'] = '0' * 64
    (fake / 'build/build-receipt.json').write_text(json.dumps(altered))
    original_module_path = module.P
    module.P = fake
    try:
        module.stage(source, root / 'receipt-not-created')
        raise AssertionError('changed build receipt accepted')
    except ValueError as error:
        assert str(error) == 'reviewed_build_receipt_changed'
    finally:
        module.P = original_module_path
    assert not (root / 'receipt-not-created').exists()
print('PASS actual ten-file private composition, manifest/hash/modes, no overwrite, source drift and symlink refusal')
