#!/usr/bin/env bash
set -euo pipefail

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter が見つかりません。"
  exit 1
fi

if [[ -z "${SUPABASE_URL:-}" ]]; then
  echo "SUPABASE_URL が未設定です。"
  echo "例: export SUPABASE_URL='https://xxxx.supabase.co'"
  exit 1
fi

if [[ -z "${SUPABASE_PUBLISHABLE_KEY:-}" ]]; then
  echo "SUPABASE_PUBLISHABLE_KEY が未設定です。"
  echo "SupabaseのPublishable Keyを環境変数に設定してください。"
  exit 1
fi

if [[ ! -d ios/Runner.xcworkspace ]]; then
  echo "iOSプロジェクトを準備します..."
  bash tool/prepare_ios.sh
fi

echo "接続デバイスを確認します..."
flutter devices

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
  echo
  echo "実機iPhoneが見つかりません。"
  echo "USB接続、iPhone側の「信頼」、Developer Modeを確認してください。"
  exit 1
fi

echo
echo "iPhone実機へSKOを起動します: $DEVICE_ID"
exec flutter run   -d "$DEVICE_ID"   --dart-define="SUPABASE_URL=$SUPABASE_URL"   --dart-define="SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY"
