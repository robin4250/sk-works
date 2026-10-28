#!/usr/bin/env bash
set -euo pipefail
adapter=lib/features/shifts/own_published_shift_repository.dart
baseline=c9ed8fd42a584bff89863c386144eaf9793e257e
scratch="$(mktemp -d "${RUNNER_TEMP:-/tmp}/sko-shift-baseline.XXXXXX")"
cp "$adapter" "$scratch/corrected.dart"
expected="$(sha256sum "$adapter" | cut -d' ' -f1)"
restore() {
  cp "$scratch/corrected.dart" "$adapter"
  test "$(sha256sum "$adapter" | cut -d' ' -f1)" = "$expected"
  rm -r "$scratch"
}
trap restore EXIT
git cat-file -e "$baseline:$adapter"
git show "$baseline:$adapter" > "$adapter"
test "$(git hash-object "$adapter")" = "$(git rev-parse "$baseline:$adapter")"
flutter test test/own_published_shift_replay_baseline_test.dart --dart-define=SKO_SHIFT_REPLAY_BASELINE=true --reporter expanded
restore
trap - EXIT
echo 'Exact original SDK replay observed; corrected adapter restored and hash verified.'
