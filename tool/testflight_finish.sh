#!/usr/bin/env bash
set -euo pipefail

# A release reviewer supplies the approved full SHA; never infer approval from latest main.
: "${SKO_AUDITED_SHA:?Set the reviewed full commit SHA before building or uploading}"
export SKO_AUDITED_SHA

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
python3 tool/testflight_provenance.py validate --manifest build/ios/sko-testflight-provenance.json >/dev/null
echo "検証済みIPAをTransporterで選択してください。Archiveからの再出力は別候補として再検査が必要です。"
exit 1
echo
echo "Xcodeで Distribute App → App Store Connect → Upload を選択してください。"

