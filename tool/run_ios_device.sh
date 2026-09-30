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
if ! command -v xcrun >/dev/null 2>&1; then
  echo "xcrun が見つかりません。Xcodeを確認してください。"
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

echo "実機インストール前チェックを実行します..."
if ! bash tool/ios_install_assistant.sh; then
  echo
  echo "実機インストール条件がまだ揃っていません。上の案内を解消後、同じコマンドを再実行してください。"
  exit 1
fi

DEVICE_ID="${1:-}"
if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID="$(flutter devices --machine | python3 -c '
import json, sys
items = json.load(sys.stdin)
physical = [
    item for item in items
    if str(item.get("targetPlatform", "")).startswith("ios")
    and not item.get("emulator", False)
]
iphones = [
    item for item in physical
    if "iphone" in str(item.get("name", "")).lower()
]
if len(iphones) == 1:
    print(iphones[0].get("id", ""))
')"
fi

if [[ -z "$DEVICE_ID" ]]; then
  echo "実機iPhoneを1台に特定できません。"
  echo "次: bash tool/device_day.sh <DEVICE_ID>"
  exit 1
fi

echo
echo "=== SKO standalone iPhone install ==="
echo "対象: $DEVICE_ID"
echo "Release版を署名付きでビルドします。Debug版は単体起動確認に使用しません。"

flutter build ios \
  --release \
  --dart-define="SUPABASE_URL=$SUPABASE_URL" \
  --dart-define="SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY"

APP_PATH="build/ios/iphoneos/Runner.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Releaseアプリが見つかりません: $APP_PATH"
  exit 1
fi

echo
echo "Release版SKOをiPhoneへインストールします..."
xcrun devicectl device install app \
  --device "$DEVICE_ID" \
  "$APP_PATH"

echo
echo "インストール済みRelease版SKOを起動します..."
xcrun devicectl device process launch \
  --device "$DEVICE_ID" \
  com.robin4250.sko

echo
echo "✓ Release版SKOをインストールしました。"
echo "✓ この版はXcode/Flutter Debuggerに依存しません。"
echo
echo "単体起動確認:"
echo "1. iPhoneでSKOを上へスワイプして完全終了"
echo "2. USBケーブルを抜く"
echo "3. iPhoneホーム画面のSKOをタップ"
echo "4. 通常起動すれば修正確認完了"
echo
echo "Hot Reload/Debugが必要な時だけ:"
echo "  bash tool/run_ios_device_debug.sh"
