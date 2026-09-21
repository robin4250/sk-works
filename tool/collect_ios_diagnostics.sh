#!/usr/bin/env bash
set -u

stamp="$(date +%Y%m%d-%H%M%S)"
out="${1:-/tmp/sko-ios-diagnostics-$stamp.txt}"

redact_env() {
  local name="$1"
  if [[ -n "${!name:-}" ]]; then echo "$name=set"; else echo "$name=unset"; fi
}

{
  echo "=== SKO iOS diagnostics ==="
  date
  echo
  echo "--- Git ---"
  git rev-parse --short HEAD 2>/dev/null || true
  git status --short 2>/dev/null || true
  echo
  echo "--- macOS / Xcode ---"
  sw_vers 2>/dev/null || true
  xcode-select -p 2>/dev/null || true
  xcodebuild -version 2>/dev/null || true
  echo
  echo "--- Xcode SDKs ---"
  xcodebuild -showsdks 2>/dev/null || true
  echo
  echo "Xcode first-launch status:"
  xcodebuild -checkFirstLaunchStatus 2>&1 || true
  echo
  echo "--- Toolchain ---"
  flutter --version 2>/dev/null || true
  pod --version 2>/dev/null || true
  python3 --version 2>/dev/null || true
  git --version 2>/dev/null || true
  echo
  echo "--- Flutter doctor ---"
  flutter doctor -v 2>/dev/null || true
  echo
  echo "--- Devices ---"
  flutter devices 2>/dev/null || true
  echo
  echo "--- Flutter devices machine-readable ---"
  flutter devices --machine 2>/dev/null || true
  echo
  echo "--- Xcode device control ---"
  xcrun devicectl list devices 2>/dev/null || true
  echo
  echo "--- USB iPhone visibility ---"
  system_profiler SPUSBDataType 2>/dev/null | grep -i -A 12 -B 2 'iPhone' || true
  echo
  echo "--- Signing identities ---"
  identity_output="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  printf '%s\n' "$identity_output"
  echo "Detected Team ID candidates:"
  printf '%s\n' "$identity_output" \
    | grep 'Apple Development' \
    | sed -nE 's/.*\(([A-Z0-9]{10})\).*/\1/p' \
    | sort -u || true
  echo
  echo "--- CocoaPods lock ---"
  if [[ -f ios/Podfile.lock ]]; then
    echo "ios/Podfile.lock exists"
    shasum -a 256 ios/Podfile.lock 2>/dev/null || true
  else
    echo "ios/Podfile.lock missing"
  fi
  echo
  echo "--- Project signing ---"
  if [[ -f ios/Runner.xcodeproj/project.pbxproj ]]; then
    grep -E "PRODUCT_BUNDLE_IDENTIFIER = |DEVELOPMENT_TEAM = " ios/Runner.xcodeproj/project.pbxproj | sort -u || true
    if [[ -d ios/Runner.xcworkspace ]]; then
      echo
      echo "Resolved Runner build settings:"
      xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -showBuildSettings 2>/dev/null \
        | grep -E "^[[:space:]]+(PRODUCT_BUNDLE_IDENTIFIER|DEVELOPMENT_TEAM|CODE_SIGN_STYLE) =" \
        | sort -u || true
    fi
  else
    echo "iOS project not generated"
  fi
  echo
  echo "--- Supabase env presence ---"
  redact_env SUPABASE_URL
  redact_env SUPABASE_PUBLISHABLE_KEY
} | tee "$out"

echo
echo "診断ログを保存しました: $out"
echo "※ Supabaseの実URL/キー値は出力していません。"
