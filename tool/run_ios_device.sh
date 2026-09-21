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
  selection="$(flutter devices --machine | python3 -c '
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
    print("OK:" + str(iphones[0].get("id", "")))
elif len(iphones) > 1:
    print("MULTIPLE")
    for item in iphones:
        print(f"{item.get('id','')}\t{item.get('name','iPhone')}")
elif physical:
    print("NO_IPHONE")
    for item in physical:
        print(f"{item.get('id','')}\t{item.get('name','iOS device')}")
else:
    print("NONE")
')"

  first_line="$(printf '%s\n' "$selection" | head -n 1)"
  case "$first_line" in
    OK:*)
      DEVICE_ID="${first_line#OK:}"
      ;;
    MULTIPLE)
      echo "複数の実機iPhoneを検出しました。起動先を自動選択しません。"
      printf '%s\n' "$selection" | tail -n +2
      echo "次: bash tool/device_day.sh <DEVICE_ID>"
      exit 1
      ;;
    NO_IPHONE)
      echo "物理iOS端末はありますが、iPhoneを特定できませんでした。"
      printf '%s\n' "$selection" | tail -n +2
      echo "iPhoneを接続するか、明示的に DEVICE_ID を指定してください。"
      exit 1
      ;;
    *)
      echo "実機iPhoneが見つかりません。"
      exit 1
      ;;
  esac
fi

if [[ -z "$DEVICE_ID" ]]; then
  echo "実機iPhoneのDEVICE_IDを決定できませんでした。"
  exit 1
fi

echo
echo "iPhone実機へSKOを起動します: $DEVICE_ID"
exec flutter run   -d "$DEVICE_ID"   --dart-define="SUPABASE_URL=$SUPABASE_URL"   --dart-define="SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY"
