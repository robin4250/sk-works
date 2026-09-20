#!/usr/bin/env bash
set -euo pipefail

if [[ -f "tool/local_supabase_env.sh" ]]; then
  source "tool/local_supabase_env.sh"
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter が見つかりません。"
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 が見つかりません。"
  exit 1
fi

if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_PUBLISHABLE_KEY:-}" ]]; then
  echo "Supabase接続値が未設定です。tool/local_supabase_env.sh を確認してください。"
  exit 1
fi

if [[ ! -d ios/Runner.xcworkspace ]]; then
  echo "iOSプロジェクトを準備します..."
  bash tool/prepare_ios.sh
fi

echo "実機起動前チェックを実行します..."
if ! bash tool/ios_install_assistant.sh; then
  echo
  echo "実機起動条件がまだ揃っていません。上の案内を解消後、同じコマンドを再実行してください。"
  exit 1
fi

DEVICE_ID="${1:-}"
if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID="$(flutter devices --machine | python3 -c '
import json, sys
items = json.load(sys.stdin)
for item in items:
    target = str(item.get("targetPlatform", ""))
    if target.startswith("ios") and not item.get("emulator", False):
        print(item.get("id", ""))
        break
')"
fi

if [[ -z "$DEVICE_ID" ]]; then
  echo "実機iPhoneが見つかりません。"
  exit 1
fi

echo
echo "iPhone実機へSKOを起動します: $DEVICE_ID"
exec flutter run   -d "$DEVICE_ID"   --dart-define="SUPABASE_URL=$SUPABASE_URL"   --dart-define="SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY"
