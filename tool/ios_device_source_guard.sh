#!/usr/bin/env bash
set -euo pipefail

fail() { echo "✗ $1" >&2; exit 1; }
[[ "$(uname -s)" == Darwin ]] || fail 'Release導入チェックはMac用です。'
command -v flutter >/dev/null 2>&1 || fail 'Flutter が見つかりません。'
command -v xcodebuild >/dev/null 2>&1 || fail 'Xcode が見つかりません。'
flutter_version="$(flutter --version | sed -nE 's/.*Flutter[[:space:]]+([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' | head -n 1)"
[[ "$flutter_version" == 3.47.5 ]] || fail 'Flutter 3.47.5 が必要です。'
xcode_version="$(xcodebuild -version | sed -n 's/^Xcode //p')"
[[ "$xcode_version" == 27.0 ]] || fail 'Xcode 27.0 が必要です。27.1は未検証です。'
[[ "$(git rev-parse --is-inside-work-tree)" == true ]] || fail 'Gitソースを確認できません。'
[[ "$(git branch --show-current)" == main ]] || fail 'mainブランチから導入してください。'
[[ -z "$(git status --porcelain --untracked-files=all)" ]] || fail '未保存のソース変更があります。破棄せず保存してください。'
head_sha="$(git rev-parse HEAD)"
if [[ "$#" -gt 0 ]]; then
  [[ "$#" == 1 && "$1" =~ ^[0-9a-f]{40}$ && "$head_sha" == "$1" ]] || fail 'ビルド開始時のソースSHAと一致しません。'
fi
# Fetch failure must stop; stale remote-tracking refs are not freshness evidence.
git fetch --quiet origin main || fail '最新mainを取得できません。'
[[ "$head_sha" == "$(git rev-parse FETCH_HEAD)" ]] || fail '取得した最新mainとソースが一致しません。'
[[ "$head_sha" == "$(git rev-parse HEAD)" && "$(git branch --show-current)" == main && -z "$(git status --porcelain --untracked-files=all)" ]] || fail '検査中にソースが変わりました。'
printf '%s\n' "$head_sha"
