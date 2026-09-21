#!/usr/bin/env bash
set -euo pipefail

echo "=== SKO Supabase reproducibility preflight ==="
echo "このスクリプトは本番DBを変更しません。"
echo

for cmd in supabase docker git; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "✗ $cmd が見つかりません"
    exit 1
  fi
done

if ! docker info >/dev/null 2>&1; then
  echo "✗ Dockerが起動していません"
  exit 1
fi

if [[ ! -f supabase/config.toml ]]; then
  echo "✗ supabase/config.toml がありません"
  echo "  Mac到着後に一度だけ: supabase init"
  echo "  その後、対象プロジェクトへ: supabase link --project-ref <PROJECT_REF>"
  exit 1
fi

mkdir -p supabase/baseline

echo "--- Supabase CLI ---"
supabase --version

echo
echo "--- linked migration history ---"
supabase migration list | tee supabase/baseline/production_migration_history.txt

echo
echo "--- remote DB lint (errors only) ---"
supabase db lint --linked --fail-on error

echo
echo "--- non-destructive public schema snapshot ---"
supabase db dump \
  --schema public \
  -f supabase/baseline/production_public_schema.sql

echo
echo "--- custom Storage schema diff ---"
supabase db diff \
  --linked \
  --schema storage \
  > supabase/baseline/production_storage_customizations.sql

echo
echo "--- Storage bucket metadata snapshot ---"
if command -v psql >/dev/null 2>&1 && [[ -n "${SUPABASE_DB_URL:-}" ]]; then
  psql "$SUPABASE_DB_URL" \
    -v ON_ERROR_STOP=1 \
    -Atc "select id, public, coalesce(file_size_limit::text,''), coalesce(array_to_string(allowed_mime_types, ','),'') from storage.buckets order by id;" \
    > supabase/baseline/production_storage_buckets.tsv
  echo "✓ Storage bucket metadata snapshot"
else
  echo "△ SUPABASE_DB_URL または psql がないためbucket metadata snapshotはスキップ"
  echo "  Storage bucketは db diff の既知の制限対象です。MacでDB URLを設定後に再実行してください。"
fi

echo
echo "--- baseline checksums ---"
: > supabase/baseline/SHA256SUMS.txt
for artifact in   supabase/baseline/production_migration_history.txt   supabase/baseline/production_public_schema.sql   supabase/baseline/production_storage_customizations.sql   supabase/baseline/production_storage_buckets.tsv; do
  if [[ -f "$artifact" ]]; then
    shasum -a 256 "$artifact" >> supabase/baseline/SHA256SUMS.txt
  fi
done
echo "✓ baseline SHA-256 manifest"

echo
echo "✓ 非破壊の再現性診断が完了しました"
echo "  migration history: supabase/baseline/production_migration_history.txt"
echo "  public schema     : supabase/baseline/production_public_schema.sql"
echo "  storage diff : supabase/baseline/production_storage_customizations.sql"
echo "  bucket meta       : supabase/baseline/production_storage_buckets.tsv（取得できた場合）"
echo "  checksums         : supabase/baseline/SHA256SUMS.txt"
echo
echo "重要:"
echo "  supabase db reset --linked は本番DBを破壊するため実行しないでください。"
echo "  db pull / migration repair / db push は生成物レビュー後に別工程で行います。"
