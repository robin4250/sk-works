"""Exercise only the new composition boundary against actual compiled files."""
import contextlib
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
source = P.parents[1]
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
print('PASS actual ten-file private composition, manifest/hash/modes, no overwrite, source drift and symlink refusal')
