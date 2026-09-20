#!/usr/bin/env bash
set -u

echo "=== SKO iPhone install assistant ==="
echo

if [[ -f "tool/local_supabase_env.sh" ]]; then
  # Local-only values. This file is gitignored.
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
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "$label"
  else
    fail "$label が見つかりません"
  fi
}

echo "--- 必須ツール ---"
command_ok "Flutter" flutter
command_ok "Xcode command line tools" xcodebuild
command_ok "CocoaPods" pod
command_ok "Git" git

echo
echo "--- Supabase ---"
if [[ -n "${SUPABASE_URL:-}" ]]; then
  ok "SUPABASE_URL"
else
  fail "SUPABASE_URL が未設定です"
fi

if [[ -n "${SUPABASE_PUBLISHABLE_KEY:-}" ]]; then
  ok "SUPABASE_PUBLISHABLE_KEY"
else
  fail "SUPABASE_PUBLISHABLE_KEY が未設定です"
fi

echo
echo "--- iOSプロジェクト ---"
if [[ -d ios/Runner.xcworkspace && -f ios/Runner.xcodeproj/project.pbxproj ]]; then
  ok "iOSプロジェクト生成済み"
else
  warn "iOSプロジェクトが未生成です"
  echo "  次: bash tool/prepare_ios.sh"
fi

if [[ -f ios/Runner.xcodeproj/project.pbxproj ]]; then
  bundle_id="$(python3 - <<'PY'
from pathlib import Path
import re

text = Path("ios/Runner.xcodeproj/project.pbxproj").read_text()
for value in re.findall(r"PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);", text):
    value = value.strip()
    if "$(" not in value and not value.endswith(".RunnerTests"):
        print(value)
        break
PY
)"
  if [[ -n "$bundle_id" ]]; then
    ok "Bundle Identifier: $bundle_id"
  else
    warn "Bundle Identifierを確認できませんでした"
  fi

  team_id="$(python3 - <<'PY'
from pathlib import Path
import re

text = Path("ios/Runner.xcodeproj/project.pbxproj").read_text()
values = [v.strip() for v in re.findall(r"DEVELOPMENT_TEAM = ([^;]*);", text)]
values = [v for v in values if v]
print(values[0] if values else "")
PY
)"
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
if command -v flutter >/dev/null 2>&1; then
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
  echo "上の ✗ を解消してください。"
  exit 1
fi

if [[ "$warnings" -gt 0 ]]; then
  echo "必須ツールとSupabase設定は揃っています。"
  echo "残りは上の △ を順番に解消してください。"
  exit 2
fi

echo "iPhone実機起動の準備が整っています。"
echo "次: bash tool/run_ios_device.sh"
