#!/usr/bin/env bash
set -euo pipefail

echo "=== SKO pre-device release gate ==="
echo

checks=(
  "bash tool/check_dependency_pins.sh"
  "bash tool/check_no_client_secrets.sh"
  "bash tool/check_migration_files.sh"
)

for cmd in "${checks[@]}"; do
  echo "--- $cmd ---"
  eval "$cmd"
  echo
done

echo "--- Shell syntax ---"
while IFS= read -r file; do
  bash -n "$file"
done < <(find tool -type f -name '*.sh' | sort)
echo "✓ Shell helper syntax"

if command -v flutter >/dev/null 2>&1; then
  echo
  echo "--- Flutter version ---"
  flutter_version="$(flutter --version 2>/dev/null | head -n 1 | awk '{print $2}')"
  if [[ "$flutter_version" != "3.47.5" ]]; then
    echo "✗ Flutter $flutter_version を検出。SKO基準は3.47.5です"
    exit 1
  fi
  echo "✓ Flutter 3.47.5"

  echo
  echo "--- Flutter dependency resolution ---"
  flutter pub get
  git diff --exit-code -- pubspec.lock
  echo "✓ pubspec.lock is stable after flutter pub get"

  echo
  echo "--- Flutter analyze ---"
  flutter analyze

  echo
  echo "--- Flutter test ---"
  flutter test

  echo
  echo "✓ Flutter static/device-independent gate"
else
  echo
  echo "△ Flutter is not installed in this environment; analyze/test skipped"
  echo "  CI still runs both checks before merge."
fi

echo
echo "=== RESULT ==="
echo "✓ Mac/iPhone-independent release gate passed"
echo "Remaining checks require Xcode signing, physical iPhone, real SMS, Face ID, camera/GPS, or iOS share/print UI."
