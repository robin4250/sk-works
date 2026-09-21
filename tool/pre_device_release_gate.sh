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
done < <(find tool -maxdepth 1 -type f -name '*.sh' | sort)
echo "✓ Shell helper syntax"

if command -v flutter >/dev/null 2>&1; then
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
