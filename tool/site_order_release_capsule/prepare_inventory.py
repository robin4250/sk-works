"""Source/catalog inventory only. No SQL execution, credentials, install or deploy."""
import argparse, hashlib, json, pathlib, re

def digest(data): return hashlib.sha256(data).hexdigest()
def entry(root,path,commit,kind):
 p=root/path
 if p.is_symlink() or not p.is_file(): raise ValueError('regular pinned source required: '+path)
 b=p.read_bytes();s=b.decode()
 return {'path':path,'commit':commit,'sha256':digest(b),'bytes':len(b),'kind':kind,
  'declared_schemas':re.findall(r'(?im)^create schema\s+([a-z_]+)',s),
  'declared_tables':re.findall(r'(?im)^create table\s+([a-z_]+\.[a-z_]+)',s),
  'declared_functions':re.findall(r'(?im)^create(?: or replace)? function\s+([a-z_]+\.[a-z_]+)\s*\(',s)}

def prepare(args):
 root=pathlib.Path(args.source_root).resolve();base=pathlib.Path(args.baseline_root).resolve()
 c=pathlib.Path(args.c_root).resolve();reply=pathlib.Path(args.reply_root).resolve();history=pathlib.Path(args.history_root).resolve();renderer=pathlib.Path(args.renderer_root).resolve()
 contract=json.loads((base/'docs/review/site-order-private-baseline/full-source-contract.json').read_text())
 files=[]
 cpath='docs/review/trade-documents-hub/master-and-standalone-context.sql.review-only'
 cfile=entry(c,cpath,'6a24114471a9c264fad1aeec5dd2222915ddbedf','master-gate-C')
 if cfile['sha256']!='7796c2e7bcc7a9eca78f1b79ce8cfc87fcd978c1dc4a4ddb7a5a8ced17b597e5': raise ValueError('C source drift')
 files.append(cfile)
 for path,expected in contract.items():
  e=entry(base,path,'14cf77f4b166bcb86d0f5fef68080841ac89a27a','private-site-baseline')
  if e['sha256']!=expected:raise ValueError('baseline drift: '+path)
  e['same_in_current_app_tree']=(root/path).is_file() and digest((root/path).read_bytes())==expected
  files.append(e)
 api='docs/candidates/trade_document_confirmation_api_20261022.sql.review-only'
 api_text=(base/api).read_text();actor=re.search(r'create function trade_document_confirmation_api_private\.actor\(\)[\s\S]*?end \$\$;',api_text).group()
 if digest(actor.encode())!='0da8df5dd78bdd44daa9757da346a48e4e7cbb63bada0b65f849cc060d2e3b15':raise ValueError('actor extraction drift')
 files.append({'path':api,'commit':'14cf77f4b166bcb86d0f5fef68080841ac89a27a','kind':'extract-one-private-actor-only','source_sha256':digest(api_text.encode()),'statement_sha256':digest(actor.encode()),'declared_functions':['trade_document_confirmation_api_private.actor'],'financial_public_rpc_installation':False})
 for r,path,sha,expected in [(reply,'docs/review/site-order-package-flow/reply-recovery.sql.review-only','de4d4bb018e8c8ca56b0c85bde09fadebca312a4','991281df5f789e1e6a3d469dd854609a065d2a6d56db33b85a08d3cf57fd9979'),(history,'docs/review/site-order-package-flow/site-history.sql.review-only','f4c6da47e8c6bd894c920ab1d85399a4dc5da7bb','0f9cc2f094e8146089a8cdf89f10fb0244ce5d80da239497b76d5c602285e577')]:
  e=entry(r,path,sha,'private-site-extension')
  if e['sha256']!=expected:raise ValueError('extension drift')
  files.append(e)
 for path in ['docs/review/site-order-outgoing/source-and-prepare-observation.sql.review-only','docs/review/site-order-outgoing/prepare-operation.sql.review-only','docs/review/site-order-outgoing/registered-targets.sql.review-only','docs/review/site-order-outgoing-consent/coordinator.sql.review-only']:
  files.append(entry(root,path,args.source_commit,'outgoing-private-purpose'))
 workflow=['supabase/functions/site-order-workflow/'+n for n in ['index.ts','runtime.mjs','auth.mjs','handler.mjs','outgoing-handler.mjs','router.mjs']]+['tool/'+n for n in ['site_order_canonical_core.mjs','site_order_outgoing_execution_contract.mjs','site_order_outgoing_delivery_core.mjs']]
 edge=[entry(root,p,args.source_commit,'fixed-edge-source')for p in workflow]
 wasm=json.loads((renderer/'source_manifest.json').read_text());drift=[]
 for path,pin in wasm['files'].items():
  if not(root/path).is_file()or digest((root/path).read_bytes())!=pin['sha256']:drift.append(path)
 if drift:raise ValueError('canonical renderer source drift: '+','.join(drift))
 renderer_files={n:{'sha256':digest((renderer/n).read_bytes()),'bytes':(renderer/n).stat().st_size}for n in ['build.py','source_manifest.json','runtime-pins.json','build-proof.json','runtime.mjs.in','edge_adapter.mjs.in','edge_entry.dart.template','combined-deno.lock']}
 out={'status':'source-only-inventory-not-an-install-approval','app_source_commit':args.source_commit,'sql_sources':files,
 'protected_exact_eight':json.loads((base/'docs/review/site-order-actual-eight/source-contract.json').read_text())['functions'],
 'edge':{'sources':edge,'renderer_tool_commit':'bb3ff2cb5ff19408ca1aa7d49e4b0f5d215e9d5d','renderer_files':renderer_files,'original_renderer_source_commit':wasm['source_commit'],'renderer_sources_verified':len(wasm['files']),'renderer_assets':len(wasm['assets']),'renderer_source_drift':drift,'expected_outputs':json.loads((renderer/'build-proof.json').read_text())['outputs'],'old_five_file_workflow_pin_reusable':False,'complete_cli_bundle_measured':False,'deployed':False},
 'guards':{'production_write_allowed':False,'feature_activation_allowed':False,'real_invitation_or_send_allowed':False,'replace_auth_or_exact_eight_allowed':False,'fixture_permission_helper_install_allowed':False,'full_financial_api_install_allowed':False,'existing_parent_binding_must_remain_unconnected':True,'existing_linked_view_must_remain_false':True}}
 out.update({'sql_sources_are_execution_order': False, 'install_order': ['C: master-and-standalone-context (preserve OFF/absent)', 'compatibility gate: unresolved payload_kind constraint and all consumer boundaries; must be reviewed before applying any order dependency', 'consent core (parent_binding raises; linked_view false; no financial API)', 'one extracted private actor only', 'artifact register', 'site manager purpose adapter', 'package foundation', 'legacy response guard (fresh full attrs)', 'approval', 'approval consent', 'archive read', 'delivery/notifications', 'read surfaces', 'archive payload', 'approval operation', 'refusal', 'reply recovery', 'site history', 'outgoing observation', 'outgoing prepare', 'registered targets', 'explicit consent coordinator'], 'readiness_blockers': ['payload_kind production CHECK excludes site_share', 'existing generic data forwarding accepts every payload kind and UI unknown kind falls back to personnel', 'legacy send_site_share would be newly unblocked by CHECK expansion', 'registered_targets has separate tests but is not installed by current consent/execution composition fixture', 'current source needs new exact Edge composition; old 1655 workflow pins are stale', 'Docker/CLI complete bundle and hosted quota/auth path not verified', 'production dependencies/Edge not deployed and feature setting row absent; no ON permission']})
 destination=pathlib.Path(args.output)
 if destination.exists()or destination.is_symlink():raise ValueError('new inventory destination required')
 destination.parent.mkdir(parents=True,exist_ok=True);destination.write_text(json.dumps(out,indent=2)+'\n')
 print(json.dumps({'sql_source_units':len(files),'edge_source_files':len(edge),'renderer_sources':len(wasm['files']),'renderer_assets':len(wasm['assets']),'source_only':True}))
if __name__=='__main__':
 p=argparse.ArgumentParser();
 for name in ['source-root','source-commit','baseline-root','c-root','reply-root','history-root','renderer-root','output']:p.add_argument('--'+name,required=True)
 prepare(p.parse_args())
