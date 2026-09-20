#!/usr/bin/env bash
set -u

echo "=== SKO iPhone install assistant ==="
echo

if [[ -f "tool/local_supabase_env.sh" ]]; then
  source "tool/local_supabase_env.sh"
fi

errors=0
warnings=0
ok() { echo "✓ $1"; }
warn() { echo "△ $1"; warnings=$((warnings + 1)); }
fail() { echo "✗ $1"; errors=$((errors + 1)); }

command_ok() {
  local label="$1"
  local cmd="$2"
  if command -v "$cmd" >/dev/null 2>&1; then ok "$label"; else fail "$label が見つかりません"; fi
}

echo "--- 必須ツール ---"
command_ok "Flutter" flutter
command_ok "Xcode command line tools" xcodebuild
command_ok "CocoaPods" pod
command_ok "Python 3" python3
command_ok "Git" git

echo
echo "--- Supabase ---"
[[ -n "${SUPABASE_URL:-}" ]] && ok "SUPABASE_URL" || fail "SUPABASE_URL が未設定です"
[[ -n "${SUPABASE_PUBLISHABLE_KEY:-}" ]] && ok "SUPABASE_PUBLISHABLE_KEY" || fail "SUPABASE_PUBLISHABLE_KEY が未設定です"

echo
echo "--- iOSプロジェクト ---"
if [[ -d ios/Runner.xcworkspace && -f ios/Runner.xcodeproj/project.pbxproj ]]; then
  ok "iOSプロジェクト生成済み"
else
  warn "iOSプロジェクトが未生成です"
  echo "  次: bash tool/prepare_ios.sh"
fi

if [[ -f ios/Runner.xcodeproj/project.pbxproj ]]; then
  bundle_id="$(grep 'PRODUCT_BUNDLE_IDENTIFIER = ' ios/Runner.xcodeproj/project.pbxproj | sed -E 's/.*PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);.*/\1/' | grep -v '\$(' | grep -v '\.RunnerTests$' | head -n 1 || true)"
  [[ -n "$bundle_id" ]] && ok "Bundle Identifier: $bundle_id" || warn "Bundle Identifierを確認できませんでした"

  team_id="$(grep 'DEVELOPMENT_TEAM = ' ios/Runner.xcodeproj/project.pbxproj | sed -E 's/.*DEVELOPMENT_TEAM = ([^;]*);.*/\1/' | grep -v '^$' | head -n 1 || true)"
  if [[ -n "$team_id" ]]; then
    ok "Signing Team設定済み: $team_id"
  else
    warn "Signing Teamが未設定です"
    echo "  次: open ios/Runner.xcworkspace"
    echo "      Runner > Signing & Capabilities"
    echo "      Automatically manage signing: ON"
    echo "      Team: Apple Account / Personal Team"
  fi
fi

echo
echo "--- iPhone接続 ---"
device_id=""
if command -v flutter >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
  device_id="$(flutter devices --machine 2>/dev/null | python3 -c '
import json, sys
try:
    items = json.load(sys.stdin)
except Exception:
    items = []
for item in items:
    target = str(item.get("targetPlatform", ""))
    if target.startswith("ios") and not item.get("emulator", False):
        print(item.get("id", ""))
        break
' 2>/dev/null || true)"
fi

if [[ -n "$device_id" ]]; then
  ok "実機iPhoneを検出: $device_id"
else
  warn "実機iPhoneをまだ検出していません"
  echo "  次: iPhoneをUSB接続 → 信頼 → Developer Mode確認"
fi

echo
echo "=== 判定 ==="
if [[ "$errors" -gt 0 ]]; then
  echo "実機起動前に必須項目が $errors 件不足しています。"
  exit 1
fi
if [[ "$warnings" -gt 0 ]]; then
  echo "残りは上の △ を順番に解消してください。"
  exit 2
fi

echo "iPhone実機起動の準備が整っています。"
echo "次: bash tool/run_ios_device.sh"
