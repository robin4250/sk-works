#!/usr/bin/env bash
set -euo pipefail

echo "=== SKO secret leak check ==="

patterns=(
  'SUPABASE_SERVICE_ROLE_KEY[[:space:]]*='
  'LINE_CHANNEL_SECRET[[:space:]]*='
  'sb_secret_[A-Za-z0-9._-]+'
  'service_role[[:space:]]*[:=][[:space:]]*["'\''][A-Za-z0-9._-]+'
)

failed=0
for pattern in "${patterns[@]}"; do
  matches="$(git grep -nE "$pattern" --     ':!docs/**'     ':!tool/check_no_secrets.sh'     ':!supabase/functions/line-webhook/index.ts'     2>/dev/null || true)"
  if [[ -n "$matches" ]]; then
    echo "✗ 秘密情報らしき文字列を検出: $pattern"
    echo "$matches"
    failed=1
  fi
done

# Environment variable names are allowed in code; literal secret values are not.
if git grep -nE 'SUPABASE_(SERVICE_ROLE|SECRET)_KEY=.+' -- ':!tool/check_no_secrets.sh' 2>/dev/null; then
  failed=1
fi

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi

echo "✓ No committed service-role / secret values detected"
