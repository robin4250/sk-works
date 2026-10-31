"""Stage fixed current owner-source + original canonical Wasm. Never deploy."""
import argparse,hashlib,json,os,pathlib
INVENTORY_SHA256='fb14c63dcd29e781cf0a30d28449da2b4377b494a0af056d0183e246c7e0cba6'
P=pathlib.Path(__file__).resolve().parent
EXPECTED_SOURCES={f'supabase/functions/site-order-workflow/{n}'for n in ['index.ts','runtime.mjs','auth.mjs','handler.mjs','outgoing-handler.mjs','router.mjs']}|{f'tool/{n}'for n in ['site_order_canonical_core.mjs','site_order_outgoing_execution_contract.mjs','site_order_outgoing_delivery_core.mjs']}
def sha(b):return hashlib.sha256(b).hexdigest()
def regular(root,name):
 p=root/name
 if p.is_symlink()or not p.is_file()or not p.resolve().is_relative_to(root):raise ValueError('regular fixed source required')
 for parent in p.parents:
  if parent==root:break
  if parent.is_symlink():raise ValueError('symlink parent forbidden')
 return p.read_bytes()
def stage(source,renderer,output):
 os.umask(0o077);source=source.resolve(strict=True);renderer=renderer.resolve(strict=True)
 if not output.is_absolute()or output.exists()or output.is_symlink():raise ValueError('new absolute private output required')
 for parent in output.parents:
  if parent.is_symlink():raise ValueError('symlink output parent forbidden')
 raw=regular(P.parents[1],'docs/review/site-order-release-capsule/source-inventory.json')
 if sha(raw)!=INVENTORY_SHA256:raise ValueError('reviewed inventory changed')
 inv=json.loads(raw);files={}
 if {e['path']for e in inv['edge']['sources']}!=EXPECTED_SOURCES:raise ValueError('unexpected source closure')
 for e in inv['edge']['sources']:
  b=regular(source,e['path'])
  if sha(b)!=e['sha256']or len(b)!=e['bytes']:raise ValueError('current owner source changed')
  files[e['path']]=b
 for name,pin in inv['edge']['renderer_files'].items():
  b=regular(renderer,name)
  if sha(b)!=pin['sha256']or len(b)!=pin['bytes']:raise ValueError('renderer tool source changed')
 for name,pin in inv['edge']['expected_outputs'].items():
  b=regular(renderer,'build/'+name)
  if sha(b)!=pin['sha256']or len(b)!=pin['bytes']:raise ValueError('canonical compiled bytes changed')
  files['supabase/functions/site-order-workflow/_canonical/'+name]=b
 files['supabase/functions/site-order-workflow/_canonical/edge_adapter.mjs']=regular(renderer,'edge_adapter.mjs.in')
 total=sum(map(len,files.values()))
 if len(files)!=14 or total>=20_000_000:raise ValueError('fixed source/static budget exceeded')
 output.mkdir(mode=0o700,parents=True)
 receipt={'app_source_commit':inv['app_source_commit'],'renderer_tool_commit':inv['edge']['renderer_tool_commit'],
  'files':{},'source_and_static_bytes':total,'complete_cli_bundle_measured':False,'hosted_quota_verified':False,
  'project_configuration_copied':False,'secrets_copied':False,'deployed':False,'production_changed':False}
 for name,data in files.items():
  dest=output/name;dest.parent.mkdir(mode=0o700,parents=True,exist_ok=True);dest.write_bytes(data);dest.chmod(0o600)
  receipt['files'][name]={'sha256':sha(data),'bytes':len(data)}
 (output/'private-current-edge-manifest.json').write_text(json.dumps(receipt,indent=2)+'\n')
 return receipt
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--source-root',type=pathlib.Path,required=True);p.add_argument('--renderer-root',type=pathlib.Path,required=True);p.add_argument('--output',type=pathlib.Path,required=True);a=p.parse_args()
 print(json.dumps(stage(a.source_root,a.renderer_root,a.output)))
