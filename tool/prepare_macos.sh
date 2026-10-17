#!/usr/bin/env bash
# New Mac worktree only. Never regenerate an existing native project.
set -euo pipefail
test "$(uname -s)" = Darwin || { echo "macOS host required"; exit 1; }
test "${SKO_ISOLATED_MAC_PREPARE:-}" = 1 || { echo "Use an isolated Mac worktree and set SKO_ISOLATED_MAC_PREPARE=1"; exit 1; }
test -f .git || { echo "A separate Git worktree is required"; exit 1; }
test ! -e macos || { echo "Existing macos preserved; refusing regeneration"; exit 1; }
test -z "$(git status --porcelain --untracked-files=all)" || { echo "Worktree changes preserved; stop"; exit 1; }
flutter --version | head -1 | grep -F 'Flutter 3.47.5 ' >/dev/null
task_temp=$(mktemp -d)
# Keep the generated temporary evidence on failure; never delete user source.
flutter create --platforms=macos --project-name sk_works --org com.skworks --no-pub "$task_temp/generated"
python3 - "$task_temp/generated/macos" <<'PY'
import pathlib,plistlib,sys
root=pathlib.Path(sys.argv[1])
info=root/'Runner/Info.plist'
with info.open('rb') as f: p=plistlib.load(f)
p['CFBundleURLTypes']=[{'CFBundleURLName':'SKO existing Google callback','CFBundleURLSchemes':['com.skworks.sko']}]
p['FlutterDeepLinkingEnabled']=False
with info.open('wb') as f: plistlib.dump(p,f)
for name in ['DebugProfile.entitlements','Release.entitlements']:
    path=root/'Runner'/name
    with path.open('rb') as f: e=plistlib.load(f)
    e['com.apple.security.network.client']=True
    e['com.apple.security.files.user-selected.read-write']=True
    with path.open('wb') as f: plistlib.dump(e,f)
config=root/'Runner/Configs/AppInfo.xcconfig'
s=config.read_text()
import re
s,n=re.subn(r'^PRODUCT_BUNDLE_IDENTIFIER = .*$', 'PRODUCT_BUNDLE_IDENTIFIER = com.skworks.skWorks', s, flags=re.M)
assert n==1
config.write_text(s)
PY
mv "$task_temp/generated/macos" macos
echo "Mac native candidate prepared. No build, login, installation or server write performed."
