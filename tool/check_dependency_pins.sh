#!/usr/bin/env bash
set -euo pipefail

if grep -Eq '^[[:space:]]+[A-Za-z0-9_]+:[[:space:]]*\^' pubspec.yaml; then
  echo "✗ pubspec.yaml に ^ バージョン指定が残っています"
  grep -En '^[[:space:]]+[A-Za-z0-9_]+:[[:space:]]*\^' pubspec.yaml
  exit 1
fi

required=(
  "supabase_flutter: 2.17.2"
  "local_auth: 2.3.0"
  "geolocator: 14.0.3"
  "image_picker: 1.1.2"
  "mobile_scanner: 7.4.2"
  "qr_flutter: 4.1.0"
  "share_plus: 13.3.0"
  "printing: 5.15.1"
  "pdf: 3.13.1"
)
for item in "${required[@]}"; do
  grep -Fq "$item" pubspec.yaml || {
    echo "✗ 必須依存の固定値が変わっています: $item"
    exit 1
  }
done

echo "✓ Direct Flutter dependencies are pinned"
if [[ -f pubspec.lock ]]; then
  echo "✓ pubspec.lock exists"
  if git check-ignore -q pubspec.lock 2>/dev/null; then
    echo "✗ pubspec.lock がGit管理対象外です"
    exit 1
  fi
else
  echo "△ pubspec.lock は未生成です。Mac初回準備時に flutter pub get で生成します。"
fi
