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

echo "最新mainのiOS生成設定をMacへ再適用します..."
bash tool/prepare_ios.sh

echo "生成済みiOS設定を検証します..."
bash tool/check_ios_generated_contract.sh

echo "実機インストール前チェックを実行します..."
if ! bash tool/ios_install_assistant.sh; then
  echo
  echo "実機インストール条件がまだ揃っていません。上の案内を解消後、同じコマンドを再実行してください。"
  exit 1
fi

DEVICE_ID="${1:-}"
if [[ -z "$DEVICE_ID" ]]; then
  device_json="$(flutter devices --machine)"
  selection="$(DEVICE_JSON="$device_json" python3 <<'PY'
import json, os
items = json.loads(os.environ.get("DEVICE_JSON", "[]"))
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
PY
)"

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

device_list="$(flutter devices --machine)"
validation="$(DEVICE_LIST="$device_list" python3 - "$DEVICE_ID" <<'PY'
import json, os, sys
wanted = sys.argv[1]
try:
    items = json.loads(os.environ.get("DEVICE_LIST", "[]"))
except Exception:
    items = []

match = next((item for item in items if str(item.get("id", "")) == wanted), None)
if match is None:
    print("MISSING")
    raise SystemExit

target = str(match.get("targetPlatform", ""))
name = str(match.get("name", ""))
emulator = bool(match.get("emulator", False))

if not target.startswith("ios") or emulator:
    print("NOT_PHYSICAL_IOS")
else:
    print("OK:" + name)
PY
)"

case "$validation" in
  OK:*)
    echo "✓ 起動対象を確認: ${validation#OK:} ($DEVICE_ID)"
    ;;
  MISSING)
    echo "指定したDEVICE_IDが現在のFlutterデバイス一覧にありません: $DEVICE_ID"
    exit 1
    ;;
  NOT_PHYSICAL_IOS)
    echo "指定したDEVICE_IDは物理iOS端末ではありません: $DEVICE_ID"
    exit 1
    ;;
  *)
    echo "DEVICE_IDの検証に失敗しました: $DEVICE_ID"
    exit 1
    ;;
esac

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

BUNDLE_ID="${SKO_IOS_BUNDLE_ID:-com.skworks.skWorks}"

echo
echo "インストール済みRelease版SKOを起動します: $BUNDLE_ID"
xcrun devicectl device process launch \
  --device "$DEVICE_ID" \
  "$BUNDLE_ID"

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
