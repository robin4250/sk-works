#!/usr/bin/env bash
# Compile readiness only, not hosting or browser authorization.
set -euo pipefail
test "${SKO_ISOLATED_WEB_PREPARE:-}" = 1 || { echo "Set SKO_ISOLATED_WEB_PREPARE=1 in a separate clean worktree"; exit 1; }
test -f .git || { echo "Separate Git worktree required"; exit 1; }
test ! -e web || { echo "Existing web project preserved; refusing regeneration"; exit 1; }
test -z "$(git status --porcelain --untracked-files=all)" || { echo "Worktree changes preserved; stop"; exit 1; }
flutter --version | head -1 | grep -F 'Flutter 3.47.5 ' >/dev/null
task_temp=$(mktemp -d)
flutter create --platforms=web --project-name sk_works --org com.skworks --no-pub "$task_temp/generated"
mv "$task_temp/generated/web" web
echo "Isolated web scaffold prepared. No hosting, login, server connection or trusted-device enrollment."
