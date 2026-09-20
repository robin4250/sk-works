#!/usr/bin/env bash
set -u

echo "=== SKO iPhone readiness check ==="
echo

if [[ -f "tool/local_supabase_env.sh" ]]; then
  source "tool/local_supabase_env.sh"
fi

status=0

check_cmd() {
  local name="$1"
  local cmd="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "✓ $name: $(command -v "$cmd")"
  else
    echo "✗ $name が見つかりません"
    status=1
  fi
}

check_cmd "Flutter" flutter
check_cmd "Xcode command line tools" xcodebuild
check_cmd "CocoaPods" pod
check_cmd "Git" git

echo
if command -v xcodebuild >/dev/null 2>&1; then
  echo "--- Xcode ---"
  xcodebuild -version || true
fi

echo
if command -v flutter >/dev/null 2>&1; then
  echo "--- Flutter doctor ---"
  flutter doctor || true
  echo
  echo "--- Flutter devices ---"
  flutter devices || true
fi

echo
echo "--- Supabase Dart defines ---"
if [[ -n "${SUPABASE_URL:-}" ]]; then
  echo "✓ SUPABASE_URL is set"
else
  echo "△ SUPABASE_URL is not set in this shell"
fi

if [[ -n "${SUPABASE_PUBLISHABLE_KEY:-}" ]]; then
  echo "✓ SUPABASE_PUBLISHABLE_KEY is set"
else
  echo "△ SUPABASE_PUBLISHABLE_KEY is not set in this shell"
fi

echo
echo "--- iOS project ---"
if [[ -d ios/Runner.xcworkspace ]]; then
  echo "✓ ios/Runner.xcworkspace exists"

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
      echo "✓ Bundle Identifier: $bundle_id"
    else
      echo "△ Bundle Identifierを確認できませんでした"
    fi
  fi
else
  echo "△ iOS project not generated yet. Run: bash tool/prepare_ios.sh"
fi

echo
if [[ "$status" -eq 0 ]]; then
  echo "基本ツールは揃っています。"
else
  echo "不足ツールがあります。上の ✗ を先に解消してください。"
fi

exit "$status"
