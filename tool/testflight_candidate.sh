#!/usr/bin/env bash
set -euo pipefail

echo "=== SKO TestFlight candidate builder ==="
echo

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "✗ このスクリプトはMac専用です。"
  exit 1
fi

if [[ -f "tool/local_supabase_env.sh" ]]; then
  source "tool/local_supabase_env.sh"
fi

if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_PUBLISHABLE_KEY:-}" ]]; then
  echo "✗ Supabase公開接続値が未設定です。"
  echo "  tool/local_supabase_env.sh を確認してください。"
  exit 1
fi

echo "[1/5] 最新mainを確認"
branch="$(git branch --show-current 2>/dev/null || true)"
if [[ "$branch" != "main" ]]; then
  echo "✗ TestFlight候補はmainから作成します。現在: ${branch:-detached}"
  exit 1
fi
git fetch --quiet origin main
if [[ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]]; then
  echo "✗ ローカルHEADがorigin/mainと一致していません。"
  exit 1
fi
echo "✓ main @ $(git rev-parse --short HEAD)"

echo
echo "[2/5] 正式アイコンとiOS設定を準備"
bash tool/prepare_ios.sh

echo
echo "[3/5] TestFlight preflight"
bash tool/testflight_preflight.sh

echo
echo "[4/5] App Store配布用Release IPAを作成"
flutter build ipa \
  --release \
  --export-method app-store \
  --dart-define="SUPABASE_URL=$SUPABASE_URL" \
  --dart-define="SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY"

ARCHIVE_APP="build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app"
EXPECTED_BUNDLE_ID="com.skworks.skWorks"
if [[ ! -d "$ARCHIVE_APP" ]]; then
  echo "✗ TestFlight archive内のRunner.appを確認できません。"
  exit 1
fi
built_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$ARCHIVE_APP/Info.plist" 2>/dev/null || true)"
if [[ "$built_bundle_id" != "$EXPECTED_BUNDLE_ID" ]]; then
  echo "✗ Bundle IDが一致しません: ${built_bundle_id:-unknown}"
  echo "  必須: $EXPECTED_BUNDLE_ID"
  exit 1
fi

echo
echo "[5/5] 候補確認"
ipa=""
for candidate in build/ios/ipa/*.ipa; do
  if [[ -f "$candidate" ]]; then
    ipa="$candidate"
    break
  fi
done
if [[ -z "$ipa" ]]; then
  echo "✗ IPAが生成されていません。"
  exit 1
fi

echo "✓ TestFlight候補IPA: $ipa"
echo "✓ Bundle Identifier: $built_bundle_id"
echo "✓ Release archive: build/ios/archive/Runner.xcarchive"
echo
echo "次は実機確認後、Xcode Organizer / App Store Connectからこの候補をTestFlightへアップロードします。"
