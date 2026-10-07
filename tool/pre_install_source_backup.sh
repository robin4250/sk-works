#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "✗ インストール前チェックはMac用です。"
  exit 1
fi

xcode_version="$(xcodebuild -version | sed -n 's/^Xcode //p')"
if [[ "$xcode_version" != "27.0" ]]; then
  echo "✗ Xcode 27.0 が必要です（検出: ${xcode_version:-不明}）。"
  exit 1
fi

git rev-parse --is-inside-work-tree >/dev/null
if [[ -n "$(git status --porcelain --untracked-files=all)" ]]; then
  echo "✗ 未保存のソース変更があります。変更を保存してからRelease導入を再実行してください。"
  echo "  内容や接続設定は出力していません。確認: git status --short"
  exit 1
fi

# This is a source recovery copy, not an iPhone or Supabase data backup.
# Ignored local credentials, generated iOS files and builds are not copied.
umask 077
backup_root="${SKO_SOURCE_BACKUP_DIR:-$HOME/SKO-source-backups}"
mkdir -p "$backup_root"
backup_dir="$(mktemp -d "$backup_root/pre-install-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")"
git rev-parse HEAD > "$backup_dir/commit.txt"
git status --porcelain --untracked-files=all > "$backup_dir/status.txt"
git bundle create "$backup_dir/source.bundle" HEAD >/dev/null 2>&1
git bundle verify "$backup_dir/source.bundle" >/dev/null 2>&1
echo "✓ Xcode 27.0 / 保存済みソースを確認"
echo "✓ ソース復旧用バックアップ: $backup_dir"
echo "  iPhone内データ・Supabaseデータのバックアップは別途必要です。"
