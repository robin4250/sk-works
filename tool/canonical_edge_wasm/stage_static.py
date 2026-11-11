"""Stage private fixed assets for a reviewed existing Edge function. Never deploy."""
import argparse,hashlib,json,pathlib,shutil
p=pathlib.Path(__file__).resolve().parent
parser=argparse.ArgumentParser();parser.add_argument('--output',type=pathlib.Path,required=True);a=parser.parse_args()
# An empty new destination prevents overwriting an existing handler/config/project.
assert not a.output.exists(), 'new_empty_destination_required'
receipt=json.loads((p/'build/build-receipt.json').read_text())
fixed=['main.wasm','main.mjs','main.support.js','runtime.mjs']
assert sum(receipt['outputs'][n]['bytes'] for n in fixed)<20*1024*1024,'CLI_static_budget_exceeded'
for name in fixed:
 data=(p/'build'/name).read_bytes();pin=receipt['outputs'][name]
 assert len(data)==pin['bytes'] and hashlib.sha256(data).hexdigest()==pin['sha256'],'compiled_artifact_changed'
# Adapter is small source, not an arbitrary user-supplied executable.
adapter=(p/'edge_adapter.mjs.in').read_bytes()
a.output.mkdir(parents=True,mode=0o700)
manifest={}
for name in fixed:
 data=(p/'build'/name).read_bytes();target=a.output/name;target.write_bytes(data);target.chmod(0o600)
 manifest[name]={'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()}
target=a.output/'edge_adapter.mjs';target.write_bytes(adapter);target.chmod(0o600)
manifest[target.name]={'bytes':len(adapter),'sha256':hashlib.sha256(adapter).hexdigest()}
(a.output/'private-artifact-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps({'staged_files':len(manifest),'total_bytes':sum(x['bytes'] for x in manifest.values()),'http_handler':False,'deployed':False,'production_changed':False}))
