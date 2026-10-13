#!/usr/bin/env bash
set -euo pipefail

echo "=== SKO tracked-secret scan ==="

fail=0

check_pattern() {
  local label="$1"
  local pattern="$2"
  local matches
  matches="$(git grep -lEI "$pattern" --     ':!tool/check_no_client_secrets.sh' 2>/dev/null || true)"
  if [[ -n "$matches" ]]; then
    echo "✗ $label"
    echo "  該当ファイル:"
    while IFS= read -r file; do
      [[ -n "$file" ]] && echo "  - $file"
    done <<< "$matches"
    fail=1
  else
    echo "✓ $label"
  fi
}

check_pattern "Supabase secret-key literal absent" 'sb_secret_[A-Za-z0-9_-]{8,}'
check_pattern "service-role env assignment absent" 'SUPABASE_SERVICE_ROLE_KEY[[:space:]]*=[[:space:]]*["'"'"']?[^$[:space:]"'"'"']'
check_pattern "LINE channel secret assignment absent" 'LINE_CHANNEL_SECRET[[:space:]]*=[[:space:]]*["'"'"']?[^$[:space:]"'"'"']'
check_pattern "legacy service-role JWT marker absent" '"role"[[:space:]]*:[[:space:]]*"service_role"'
check_pattern "JWT-like secret absent" 'eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}'
check_pattern "hard-coded bearer token absent" 'Authorization:[[:space:]]*Bearer[[:space:]]+[A-Za-z0-9._-]{30,}'

if [[ "$fail" -ne 0 ]]; then
  echo "Tracked secret-like value detected."
  exit 1
fi

echo "✓ No tracked production secret literals detected"
