#!/usr/bin/env bash
set -u

echo "=== SKO TestFlight preflight ==="
echo

errors=0
warnings=0
ok() { echo "✓ $1"; }
warn() { echo "△ $1"; warnings=$((warnings + 1)); }
fail() { echo "✗ $1"; errors=$((errors + 1)); }

if [[ "$(uname -s)" != "Darwin" ]]; then
  fail "このスクリプトはMac用です"
  exit 1
fi

echo "--- Git / main freshness ---"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch="$(git branch --show-current 2>/dev/null || true)"
  head="$(git rev-parse --short HEAD 2>/dev/null || true)"
  [[ "$branch" == "main" ]] && ok "main @ $head" || fail "TestFlight候補はmainから作成してください: ${branch:-detached}"
  if git fetch --quiet origin main 2>/dev/null; then
    if [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]]; then
      ok "origin/main と一致"
    else
      fail "ローカルmainがorigin/mainと一致していません"
    fi
  else
    warn "origin/mainを取得できませんでした"
  fi
else
  fail "Gitリポジトリを確認できません"
fi

echo
echo "--- Toolchain ---"
for cmd in flutter xcodebuild xcrun pod security; do
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "$cmd"
  else
    fail "$cmd が見つかりません"
  fi
done

if command -v flutter >/dev/null 2>&1; then
  version="$(flutter --version 2>/dev/null | head -n 1 | awk '{print $2}')"
  [[ "$version" == "3.47.5" ]] && ok "Flutter 3.47.5" || fail "Flutter $version（SKO基準は3.47.5）"
fi

echo
echo "--- Release project contract ---"
if [[ -f ios/Runner.xcodeproj/project.pbxproj ]]; then
  bundle="$(grep 'PRODUCT_BUNDLE_IDENTIFIER = ' ios/Runner.xcodeproj/project.pbxproj | sed -E 's/.*PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);.*/\1/' | grep -v '\$(' | grep -v '\.RunnerTests$' | head -n 1 || true)"
  [[ "$bundle" == "com.skworks.skWorks" ]] && ok "Bundle Identifier: $bundle" || fail "Bundle Identifierを確認: ${bundle:-unknown}（必須: com.skworks.skWorks）"

  team="$(grep 'DEVELOPMENT_TEAM = ' ios/Runner.xcodeproj/project.pbxproj | sed -E 's/.*DEVELOPMENT_TEAM = ([^;]*);.*/\1/' | grep -v '^$' | head -n 1 || true)"
  [[ -n "$team" ]] && ok "Signing Team: $team" || warn "Signing Teamが未設定です"

  if grep -q 'CODE_SIGN_STYLE = Automatic;' ios/Runner.xcodeproj/project.pbxproj; then
    ok "Automatically manage signing"
  else
    warn "Automatic signing設定を確認してください"
  fi
else
  fail "iOS Xcode projectがありません"
fi

scheme="ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme"
if [[ -f "$scheme" ]]; then
  if python3 - "$scheme" <<'PY'
from pathlib import Path
import re, sys
text = Path(sys.argv[1]).read_text()
m = re.search(r'<LaunchAction\b[\s\S]*?buildConfiguration = "([^"]+)"', text)
raise SystemExit(0 if m and m.group(1) == "Release" else 1)
PY
  then
    ok "Xcode Run = Release"
  else
    fail "Xcode Run構成がReleaseではありません"
  fi
else
  fail "Runner.xcschemeがありません"
fi

echo
echo "--- Signing identity ---"
if command -v security >/dev/null 2>&1; then
  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  if echo "$identities" | grep -Eq 'Apple Distribution|Apple Development'; then
    ok "Apple codesigning identityを検出"
  else
    warn "Apple署名証明書を検出できません"
  fi
fi

echo
echo "--- Gate ---"
if bash tool/pre_device_release_gate.sh; then
  ok "pre-device release gate"
else
  fail "pre-device release gate"
fi

echo
echo "=== 判定 ==="
if [[ "$errors" -gt 0 ]]; then
  echo "TestFlight候補作成前に必須項目が $errors 件あります。"
  exit 1
fi
if [[ "$warnings" -gt 0 ]]; then
  echo "コード側の必須条件は通過しました。Apple署名/Account側の△が $warnings 件あります。"
  exit 2
fi
echo "TestFlight候補を作成できるコード/署名準備です。"
echo "次工程ではApp Store Connect用のArchive/Uploadを行います。"
