#!/usr/bin/env bash
set -euo pipefail

echo "=== SKO committed-secret scan ==="

bad=0

scan() {
  local pattern="$1"
  local label="$2"
  local matches
  matches="$(git grep -nEI "$pattern" -- .     ':(exclude)tool/check_no_committed_secrets.sh'     ':(exclude)docs/**' 2>/dev/null || true)"
  if [[ -n "$matches" ]]; then
    echo "✗ $label の可能性がある文字列を検出しました"
    echo "$matches"
    bad=1
  fi
}

scan 'SUPABASE_SERVICE_ROLE_KEY[[:space:]]*=[[:space:]]*["'\'' ]*[A-Za-z0-9._-]{20,}' 'Supabase service role key'
scan 'sb_secret_[A-Za-z0-9_-]{16,}' 'Supabase secret key'
scan 'LINE_CHANNEL_SECRET[[:space:]]*=[[:space:]]*["'\'' ]*[A-Za-z0-9+/=_-]{16,}' 'LINE channel secret value'
scan 'Authorization:[[:space:]]*Bearer[[:space:]]+[A-Za-z0-9._-]{30,}' 'hard-coded bearer token'

if [[ "$bad" -ne 0 ]]; then
  exit 1
fi

echo "✓ No committed high-risk secrets detected"
