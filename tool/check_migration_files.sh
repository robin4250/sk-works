#!/usr/bin/env bash
set -euo pipefail

echo "=== SKO migration file check ==="

tmp_files="$(mktemp)"
tmp_seen="$(mktemp)"
trap 'rm -f "$tmp_files" "$tmp_seen"' EXIT

find supabase/migrations -type f -name '*.sql' | sort > "$tmp_files"

if [[ ! -s "$tmp_files" ]]; then
  echo "✗ migration SQL がありません"
  exit 1
fi

failed=0

while IFS= read -r path; do
  name="$(basename "$path")"
  if [[ ! "$name" =~ ^[0-9]{8,14}_[a-z0-9_]+\.sql$ ]]; then
    echo "✗ migrationファイル名形式が不正: $name"
    failed=1
    continue
  fi

  version="${name%%_*}"
  if grep -Fxq "$version" "$tmp_seen"; then
    echo "✗ migration version重複: $version"
    failed=1
  else
    printf '%s\n' "$version" >> "$tmp_seen"
  fi
done < "$tmp_files"

required=(
  "20260919010000_reconcile_chat_line_schema.sql"
  "20260920213500_revoke_anon_public_table_access.sql"
  "20260920224500_restrict_company_members_self_read.sql"
  "20260920225500_restrict_line_binding_visibility.sql"
)

for name in "${required[@]}"; do
  if [[ ! -f "supabase/migrations/$name" ]]; then
    echo "✗ 必須reconciliation/security migrationがありません: $name"
    failed=1
  fi
done

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi

echo "✓ Migration filenames and required reconciliation points are valid"
