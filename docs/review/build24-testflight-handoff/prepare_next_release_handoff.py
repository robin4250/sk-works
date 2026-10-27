"""Prepare one Mac command; never build or upload from this environment."""
import argparse
import ast
import pathlib
import re
import shlex

parser = argparse.ArgumentParser()
parser.add_argument('--approved-sha', required=True)
parser.add_argument('--unused-build', required=True, type=int)
parser.add_argument('--output', required=True, type=pathlib.Path)
args = parser.parse_args()
if not re.fullmatch(r'[0-9a-f]{40}', args.approved_sha) or args.unused_build < 23:
    parser.error('reviewed commit and unused build >=23 required')
template = pathlib.Path(__file__).with_name('mac-build22-command.txt').read_text()
tokens = shlex.split(template)
assert tokens[:2] == ['python3', '-c'] and len(tokens) == 3
code = tokens[2].replace('986ac4d51d9c0298d5cd04a6d38d8d373f697094', args.approved_sha)
code = code.replace('必須CIの成功を待ち、build 22のReleaseを作成します。',
                    f'必須CIの成功を確認し、build {args.unused_build}のReleaseを作成します。')
code = code.replace(')<22', f')<{args.unused_build}')
code = code.replace('"--unused-build-number","22"', f'"--unused-build-number","{args.unused_build}"')
assert '; sys.exit(' in code
prefix, final = code.rsplit('; ', 1)
node = ast.parse(final).body[0].value
assert isinstance(node, ast.Call) and ast.unparse(node.func) == 'sys.exit'
run = node.args[0].value
assert ast.unparse(run.func) == 'subprocess.run'
run.keywords.append(ast.keyword(arg='check', value=ast.Constant(True)))
invoke = ast.unparse(run)
after = '''new=[p for p in bk.glob("tf-candidate-*") if p.is_dir() and p.name not in before]; assert len(new)==1,"Inspect candidate; do not rebuild"; stage=new[0]; c=json.loads((stage/"complete-private.json").read_text()); m=json.loads((stage/"source/build/ios/sko-testflight-provenance.json").read_text()); assert c["sha"]==m["commit"]==s; assert str(c["build_number"])==str(m["build"])==str(NUMBER); ps=list((stage/"source/build/ios/ipa").glob("*.ipa")); assert len(ps)==1; ipa=ps[0]; digest=hashlib.sha256(); stream=ipa.open("rb"); exec("for chunk in iter(lambda:stream.read(1048576),b\\"\\"):\\n digest.update(chunk)"); stream.close(); assert digest.hexdigest()==c["ipa_sha256"]==m["sha256"]; import zipfile,plistlib; z=zipfile.ZipFile(ipa); plists=[n for n in z.namelist() if n.startswith("Payload/") and n.count("/")==2 and n.endswith(".app/Info.plist")]; assert len(plists)==1; info=plistlib.loads(z.read(plists[0])); assert info["CFBundleIdentifier"]=="com.skworks.skWorks" and str(info["CFBundleVersion"])==str(NUMBER) and m["distribution"]=="app-store"; z.close(); subprocess.run(["open","-a","Transporter",str(ipa)],check=True); print("検証済みIPAをTransporterへ開きました。アップロードはしていません。")'''
after = after.replace('NUMBER', str(args.unused_build))
guard_sha = 'd86b881d2918093b2aface8050a0d1e3acab05f4'
guard_digest = 'fe264a6608873199e2e2f3f726232547d30ba8c6b6bb021133c53113ae1f9fa9'
# Ask the owner to inspect App Store Connect: no authenticated ASC query is available.
asc = f'; answer=input("App Store Connectでビルド {args.unused_build} が未使用と確認した場合のみ 未使用 {args.unused_build} と入力してください: "); assert answer=="未使用 {args.unused_build}", "Apple側未確認: 作成しません"'
guard = ('; subprocess.run(["git","-C",r,"fetch","--no-tags","--no-write-fetch-head","origin","' + guard_sha + '"],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL); '
         'b=subprocess.check_output(["git","-C",r,"show","' + guard_sha + ':docs/review/build24-testflight-handoff/testflight_private_candidate.py"]); '
         'assert hashlib.sha256(b).hexdigest()=="' + guard_digest + '"; (d/"testflight_private_candidate.py").write_bytes(b)')
code = prefix + asc + guard + '; before={p.name for p in bk.glob("tf-candidate-*") if p.is_dir()}; ' + invoke + '; ' + after
ast.parse(code)
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text('env PYTHONOPTIMIZE=0 python3 -c ' + shlex.quote(code) + '\n')
print('Command prepared; no Mac operation, build or upload executed.')
