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
supabase migration list --linked

echo
echo "--- remote DB lint (errors only) ---"
supabase db lint --linked --fail-on error

echo
echo "--- non-destructive public schema snapshot ---"
supabase db dump \
  --linked \
  --schema public \
  --file supabase/baseline/production_public_schema.sql

echo
echo "--- custom Storage schema diff ---"
supabase db diff \
  --linked \
  --schema storage \
  --output supabase/baseline/production_storage_customizations.sql

echo
echo "✓ 非破壊の再現性診断が完了しました"
echo "  public schema: supabase/baseline/production_public_schema.sql"
echo "  storage diff : supabase/baseline/production_storage_customizations.sql"
echo
echo "重要:"
echo "  supabase db reset --linked は本番DBを破壊するため実行しないでください。"
echo "  db pull / migration repair / db push は生成物レビュー後に別工程で行います。"
