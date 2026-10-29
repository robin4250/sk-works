#!/usr/bin/env bash
set -euo pipefail

# A release reviewer supplies the approved full SHA; never infer approval from latest main.
: "${SKO_AUDITED_SHA:?Set the reviewed full commit SHA before building or uploading}"
export SKO_AUDITED_SHA

echo "=== SKO TestFlight uploader ==="
echo

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "✗ このスクリプトはMac専用です。"
  exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "✗ xcrun が見つかりません。Xcodeを確認してください。"
  exit 1
fi

branch="$(git branch --show-current 2>/dev/null || true)"
if [[ "$branch" != "main" ]]; then
  echo "✗ TestFlightアップロードはmainから行います。現在: ${branch:-detached}"
  exit 1
fi

git fetch --quiet --no-tags origin refs/heads/main
if [[ "$(git rev-parse HEAD)" != "$(git rev-parse FETCH_HEAD)" ]]; then
  echo "✗ ローカルmainがorigin/mainと一致していません。"
  exit 1
fi

manifest="build/ios/sko-testflight-provenance.json"
ipa="$(python3 tool/testflight_provenance.py validate --manifest "$manifest")"
if [[ -z "$ipa" ]]; then
  echo "✗ IPAが見つかりません。先に bash tool/testflight_candidate.sh を実行してください。"
  exit 1
fi

key_id="${APP_STORE_CONNECT_API_KEY_ID:-}"
issuer_id="${APP_STORE_CONNECT_API_ISSUER_ID:-}"
if [[ -z "$key_id" || -z "$issuer_id" ]]; then
  echo "✗ App Store Connect APIキー情報が未設定です。"
  echo "  必要: APP_STORE_CONNECT_API_KEY_ID"
  echo "  必要: APP_STORE_CONNECT_API_ISSUER_ID"
  echo "  秘密鍵: ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8"
  exit 1
fi

key_file="${APP_STORE_CONNECT_API_KEY_PATH:-}"
if [[ -z "$key_file" ]]; then
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
if [[ -z "$key_file" || ! -f "$key_file" ]]; then
  echo "✗ App Store Connect API秘密鍵が見つかりません。"
  echo "  APP_STORE_CONNECT_API_KEY_PATH または標準配置を確認してください。"
  exit 1
fi

echo "✓ main @ $(git rev-parse --short HEAD)"
echo "✓ IPA: $ipa"
echo "✓ App Store Connect認証設定を確認しました"
echo
echo "App Store Connectへアップロードします..."

upload_staging="$(mktemp -d "${TMPDIR:-/tmp}/sko-testflight-upload.XXXXXX")"
trap 'rm -f "$upload_staging/candidate.ipa"; rmdir "$upload_staging" 2>/dev/null || true' EXIT
verified_ipa="$(python3 tool/testflight_provenance.py stage --manifest "$manifest" --staging-dir "$upload_staging")"

xcrun altool \
  --upload-app \
  --type ios \
  --file "$verified_ipa" \
  --apiKey "$key_id" \
  --apiIssuer "$issuer_id"

echo
echo "✓ TestFlightアップロード要求を送信しました。"
echo "App Store Connect側の処理完了後、TestFlightビルドとして表示されます。"

