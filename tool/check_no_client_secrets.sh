#!/usr/bin/env bash
set -euo pipefail

echo "=== SKO tracked-secret scan ==="

fail=0

check_pattern() {
  local label="$1"
  local pattern="$2"
  local matches
  matches="$(git grep -nEI "$pattern" --     ':!docs/**'     ':!tool/check_no_client_secrets.sh'     ':!supabase/functions/line-webhook/index.ts' 2>/dev/null || true)"
  if [[ -n "$matches" ]]; then
    echo "✗ $label"
    echo "$matches"
    fail=1
  else
    echo "✓ $label"
  fi
}

check_pattern "Supabase secret-key literal absent" 'sb_secret_[A-Za-z0-9_-]{8,}'
check_pattern "service-role env assignment absent" 'SUPABASE_SERVICE_ROLE_KEY[[:space:]]*=[[:space:]]*["'"'"']?[^$[:space:]"'"'"']'
check_pattern "LINE channel secret assignment absent" 'LINE_CHANNEL_SECRET[[:space:]]*=[[:space:]]*["'"'"']?[^$[:space:]"'"'"']'
check_pattern "legacy service-role JWT marker absent" '"role"[[:space:]]*:[[:space:]]*"service_role"'

if [[ "$fail" -ne 0 ]]; then
  echo "Tracked secret-like value detected."
  exit 1
fi

echo "✓ No tracked production secret literals detected"
