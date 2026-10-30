"""Offline experiment. Verify frozen source/assets, copy, one asset-loader hook.
No app source, SQL, Auth, network, production deployment or secrets are changed.
"""
import argparse,base64,gzip,hashlib,json,pathlib,shutil,subprocess
P=pathlib.Path(__file__).resolve().parent
p=argparse.ArgumentParser();p.add_argument('--source-root',type=pathlib.Path,required=True);p.add_argument('--dart',required=True);p.add_argument('--asset-encoding',choices=['raw','gzip'],default='gzip');a=p.parse_args()
(P/'build/out').mkdir(parents=True,exist_ok=True)
shutil.copyfile(P/'synthetic-cases.json',P/'build/cases.json')
manifest=json.loads((P/'source_manifest.json').read_text());source=a.source_root.resolve();out=P/'build/frozen';out.mkdir(parents=True,exist_ok=True)
verified={}
for name,pin in manifest['files'].items():
 data=(source/name).read_bytes()
 assert hashlib.sha256(data).hexdigest()==pin['sha256'], 'source changed: '+name
 assert hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()==pin['git_blob'],name
 target=out/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data);verified[name]=pin['sha256']
for n in ['pubspec.yaml','pubspec.lock']:shutil.copyfile(source/'tool/canonical_renderer'/n,out/n)
assets={}
for name,pin in manifest['assets'].items():
 data=(source/name).read_bytes();assert hashlib.sha256(data).hexdigest()==pin['sha256'],name
 assets[name]=base64.b64encode(gzip.compress(data,mtime=0) if a.asset_encoding=='gzip' else data).decode()
# The single explicit frozen-closure hook. All other copied renderer files
# remain byte-identical. The new JS entry point is not an edited renderer.
loader="""import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:archive/archive.dart';
const _compressed=%s;
const _assets=<String,String>{%s};
const _hashes=<String,String>{%s};
final _decoded=<String,Uint8List>{};
Future<ByteData> load(String path) async {
 final encoded=_assets[path],expected=_hashes[path];
 if(encoded==null||expected==null)throw StateError('canonical_asset_rejected');
 final bytes=_decoded.putIfAbsent(path,(){
  final packed=base64.decode(encoded);
  final value=_compressed?Uint8List.fromList(GZipDecoder().decodeBytes(packed)):packed;
  if(crypto.sha256.convert(value).toString()!=expected)throw StateError('canonical_asset_rejected');
  return value;
 });
 return ByteData.sublistView(bytes);
}
Future<String> loadString(String path) async {
 final value=await load(path);
 return utf8.decode(value.buffer.asUint8List(value.offsetInBytes,value.lengthInBytes));
}
"""%('true' if a.asset_encoding=='gzip' else 'false',','.join(json.dumps(k)+':'+json.dumps(v) for k,v in assets.items()),','.join(json.dumps(k)+':'+json.dumps(v['sha256']) for k,v in manifest['assets'].items()))
hook='lib/features/shared/company_pdf_assets_io.dart';(out/hook).write_text(loader)
shutil.copyfile(P/'edge_entry.dart.template',out/'edge_entry.dart')
subprocess.run([a.dart,'pub','get','--offline','--enforce-lockfile'],cwd=out,check=True)
subprocess.run([a.dart,'compile','wasm','--no-source-maps','-o',str(P/'build/main.wasm'),'edge_entry.dart'],cwd=out,check=True)
receipt={'verified_renderer_and_dependency_files':len(verified),'verified_assets':len(assets),'asset_encoding':a.asset_encoding,'source_unchanged':True,'hook':hook,'hook_sha256':hashlib.sha256(loader.encode()).hexdigest(),'entry_sha256':hashlib.sha256((P/'edge_entry.dart.template').read_bytes()).hexdigest(),'outputs':{}}
for f in sorted((P/'build').glob('main.*')):
 if f.is_file():receipt['outputs'][f.name]={'bytes':f.stat().st_size,'sha256':hashlib.sha256(f.read_bytes()).hexdigest()}
wasm_sha=receipt['outputs']['main.wasm']['sha256']
(P/'build/runtime.mjs').write_text((P/'runtime.mjs.in').read_text().replace('@WASM_SHA256@',wasm_sha))
receipt['outputs']['runtime.mjs']={'bytes':(P/'build/runtime.mjs').stat().st_size,'sha256':hashlib.sha256((P/'build/runtime.mjs').read_bytes()).hexdigest()}
(P/'build/build-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps(receipt))
