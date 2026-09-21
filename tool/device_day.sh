#!/usr/bin/env bash
set -eu

echo "=== SKO iPhone device-day runner ==="
echo

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "✗ このスクリプトはMac用です。"
  exit 1
fi

echo "[1/4] Mac初回準備を確認します"
set +e
bash tool/mac_first_run.sh
status=$?
set -e
if [[ "$status" -ne 0 ]]; then
  echo
  if [[ "$status" -eq 2 ]]; then
    echo "Mac初回準備に確認事項が残っています。上の △ を解消して同じコマンドを再実行してください。"
  else
    echo "Mac初回準備に必須の不足があります。上の ✗ を解消して同じコマンドを再実行してください。"
  fi
  echo "原因調査用ログ: bash tool/collect_ios_diagnostics.sh"
  exit "$status"
fi

echo
echo "[2/4] Mac/iPhone非依存のrelease gateを実行します"
set +e
bash tool/pre_device_release_gate.sh
status=$?
set -e
if [[ "$status" -ne 0 ]]; then
  echo
  echo "release gateで問題が見つかりました。上の ✗ を修正して同じコマンドを再実行してください。"
  exit "$status"
fi

echo
echo "[3/4] 実機当日の一括プリフライトを実行します"
set +e
bash tool/device_day_preflight.sh
status=$?
set -e
if [[ "$status" -ne 0 ]]; then
  echo
  if [[ "$status" -eq 2 ]]; then
    echo "実機固有の確認事項が残っています。上の △ を解消して同じコマンドを再実行してください。"
  else
    echo "実機起動の必須条件が不足しています。上の ✗ を解消して同じコマンドを再実行してください。"
  fi
  echo "原因調査用ログ: bash tool/collect_ios_diagnostics.sh"
  exit "$status"
fi

echo
echo "[4/4] SKOをiPhoneへ起動します"
if [[ "$#" -gt 0 ]]; then
  exec bash tool/run_ios_device.sh "$1"
else
  exec bash tool/run_ios_device.sh
fi
