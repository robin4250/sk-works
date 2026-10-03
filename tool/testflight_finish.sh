#!/usr/bin/env bash
set -euo pipefail

echo "=== SKO TestFlight fastest path ==="
echo

bash tool/testflight_candidate.sh

key_id="${APP_STORE_CONNECT_API_KEY_ID:-}"
issuer_id="${APP_STORE_CONNECT_API_ISSUER_ID:-}"
key_file="${APP_STORE_CONNECT_API_KEY_PATH:-}"
if [[ -z "$key_file" && -n "$key_id" ]]; then
  for candidate in \
    "$HOME/.appstoreconnect/private_keys/AuthKey_${key_id}.p8" \
    "$HOME/.private_keys/AuthKey_${key_id}.p8"
  do
    if [[ -f "$candidate" ]]; then
      key_file="$candidate"
      break
    fi
  done
fi

if [[ -n "$key_id" && -n "$issuer_id" && -n "$key_file" && -f "$key_file" ]]; then
  echo
  echo "App Store Connect APIキーを確認しました。アップロードへ進みます。"
  exec bash tool/testflight_upload.sh
fi

archive="build/ios/archive/Runner.xcarchive"
if [[ ! -d "$archive" ]]; then
  echo "✗ Archiveが見つかりません: $archive"
  exit 1
fi

echo
echo "App Store Connect APIキーが未設定なので、Xcode Organizerで続行します。"
echo "Archive: $archive"
open "$archive"
echo
echo "Xcodeで Distribute App → App Store Connect → Upload を選択してください。"
