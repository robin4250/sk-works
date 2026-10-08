#!/usr/bin/env bash
# Isolated Git fixture. No Mac signing or user checkout is modified.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/sko-generated-ignore-XXXXXX")"
trap 'rm -rf "$fixture_root"' EXIT
cd "$fixture_root"
git init -q
git config user.name 'SKO isolated test'
git config user.email 'test@example.invalid'
cp "$repo_root/.gitignore" .gitignore
mkdir -p lib ios/Runner.xcodeproj .idea
printf 'committed source\n' > lib/main.dart
git add .gitignore lib/main.dart
git commit -qm fixture
printf 'DEVELOPMENT_TEAM = PRESERVE;\n' > ios/Runner.xcodeproj/project.pbxproj
printf 'local workspace\n' > .idea/workspace.xml
printf 'local metadata\n' > .metadata
printf 'local module\n' > sk_works.iml
cp ios/Runner.xcodeproj/project.pbxproj "$fixture_root/signing-before.txt"
# Test helper is outside the worktree status under .git; no broad ignore exception.
mv signing-before.txt .git/signing-before.txt
[[ -z "$(git status --porcelain --untracked-files=all)" ]]
printf 'edited source\n' > lib/main.dart
[[ "$(git status --porcelain --untracked-files=all)" == *' M lib/main.dart'* ]]
printf 'new source\n' > lib/new.dart
[[ "$(git status --porcelain --untracked-files=all)" == *'?? lib/new.dart'* ]]
# Root-only generated exclusions must not hide source nested elsewhere.
mkdir -p lib/ios
printf 'real nested source\n' > lib/ios/custom.dart
[[ "$(git status --porcelain --untracked-files=all)" == *'?? lib/ios/custom.dart'* ]]
cmp ios/Runner.xcodeproj/project.pbxproj .git/signing-before.txt
[[ "$(cat .idea/workspace.xml)" == 'local workspace' ]]
[[ "$(cat .metadata)" == 'local metadata' ]]
[[ "$(cat sk_works.iml)" == 'local module' ]]
echo 'PASS: generated roots ignored; tracked/new source still detected; signing and local files preserved'
