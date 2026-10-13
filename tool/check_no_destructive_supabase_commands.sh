#!/usr/bin/env bash
set -euo pipefail

echo "=== SKO destructive Supabase command guard ==="

pattern='^[[:space:]]*(supabase[[:space:]]+db[[:space:]]+reset[[:space:]]+--linked|supabase[[:space:]]+db[[:space:]]+push([[:space:]]|$)|supabase[[:space:]]+migration[[:space:]]+repair([[:space:]]|$))'

matches="$(grep -nEH "$pattern" tool/*.sh 2>/dev/null || true)"
if [[ -n "$matches" ]]; then
  echo "✗ Destructive Supabase helper command detected"
  printf '%s
' "$matches"
  exit 1
fi

echo "✓ No destructive Supabase helper commands"
