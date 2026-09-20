#!/usr/bin/env bash
set -u

echo "=== SKO iPhone device-day runner ==="
echo

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "✗ このスクリプトはMac用です。"
  exit 1
fi

if [[ -f "tool/local_supabase_env.sh" ]]; then
  source "tool/local_supabase_env.sh"
fi

echo "[1/3] Mac初回準備を確認します"
if ! bash tool/mac_first_run.sh; then
  status=$?
  if [[ "$status" -ne 2 ]]; then
    echo
    echo "Mac初回準備に必須の不足があります。上の案内を解消して再実行してください。"
    exit "$status"
  fi
fi

echo
echo "[2/3] iPhone実機インストール条件を確認します"
if ! bash tool/ios_install_assistant.sh; then
  status=$?
  echo
  echo "実機固有の設定が残っています。上の △ / ✗ を解消して再実行してください。"
  echo "原因調査用ログ: bash tool/collect_ios_diagnostics.sh"
  exit "$status"
fi

echo
echo "[3/3] SKOをiPhoneへ起動します"
echo "接続済みiPhoneへSupabase設定付きで起動します。"
if [[ "$#" -gt 0 ]]; then
  exec bash tool/run_ios_device.sh "$1"
else
  exec bash tool/run_ios_device.sh
fi
