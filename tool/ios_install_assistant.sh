#!/usr/bin/env bash
set -u

echo "=== SKO iPhone install assistant ==="
echo

if [[ -f "tool/local_supabase_env.sh" ]]; then
  source "tool/local_supabase_env.sh"
fi

errors=0
warnings=0
ok() { echo "✓ $1"; }
warn() { echo "△ $1"; warnings=$((warnings + 1)); }
fail() { echo "✗ $1"; errors=$((errors + 1)); }

command_ok() {
  local label="$1"
  local cmd="$2"
  if command -v "$cmd" >/dev/null 2>&1; then ok "$label"; else fail "$label が見つかりません"; fi
}

echo "--- 必須ツール ---"
command_ok "Flutter" flutter
command_ok "Xcode command line tools" xcodebuild
command_ok "CocoaPods" pod
command_ok "Python 3" python3
command_ok "Git" git

echo
echo "--- Xcode / 署名 ---"
if command -v xcodebuild >/dev/null 2>&1; then
  if xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
    ok "Xcode初回処理完了"
  else
    warn "Xcodeの初回処理が未完了です"
    echo "  Xcodeを一度起動してライセンス/追加コンポーネントを完了してください。"
    echo "  CLIで進める場合: sudo xcodebuild -runFirstLaunch"
  fi

  if xcodebuild -showsdks >/dev/null 2>&1; then
    ok "Xcode SDK一覧を取得可能"
  else
    warn "Xcode SDKを読み込めません"
    echo "  Xcodeライセンス・追加コンポーネント・Developer Directoryを確認してください。"
  fi
fi

if command -v xcode-select >/dev/null 2>&1; then
  developer_dir="$(xcode-select -p 2>/dev/null || true)"
  if [[ "$developer_dir" == *"/Xcode.app/Contents/Developer" ]]; then
    ok "Xcode選択済み: $developer_dir"
  elif [[ -n "$developer_dir" ]]; then
    warn "現在のDeveloper Directory: $developer_dir"
    echo "  Xcode本体を使う場合: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  fi
fi

signing_team_candidate=""
if command -v security >/dev/null 2>&1; then
  identity_output="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  identity_count="$(printf '%s\n' "$identity_output" | grep -c 'Apple Development' || true)"
  if [[ "${identity_count:-0}" -gt 0 ]]; then
    ok "Apple Development署名証明書を検出"
    signing_team_candidate="$(
      printf '%s\n' "$identity_output" \
        | grep 'Apple Development' \
        | sed -nE 's/.*\(([A-Z0-9]{10})\).*/\1/p' \
        | sort -u \
        | head -n 1
    )"
    if [[ -n "$signing_team_candidate" ]]; then
      ok "Signing Team候補: $signing_team_candidate"
    fi
  else
    warn "Apple Development署名証明書をまだ検出していません"
    echo "  次: Xcode > Settings > Accounts でApple Accountにサインイン"
    echo "      Runner > Signing & Capabilities でPersonal Teamを選択"
  fi
fi

echo
echo "--- Supabase ---"
if [[ -n "${SUPABASE_URL:-}" && "$SUPABASE_URL" == https://*.supabase.co ]]; then
  ok "SUPABASE_URL"
else
  fail "SUPABASE_URL が未設定または形式が不正です"
fi

if [[ -n "${SUPABASE_PUBLISHABLE_KEY:-}" && "$SUPABASE_PUBLISHABLE_KEY" != "YOUR_PUBLISHABLE_KEY" ]]; then
  ok "SUPABASE_PUBLISHABLE_KEY"
else
  fail "SUPABASE_PUBLISHABLE_KEY が未設定です"
fi

echo
echo "--- iOSプロジェクト ---"
if [[ -d ios/Runner.xcworkspace && -f ios/Runner.xcodeproj/project.pbxproj ]]; then
  ok "iOSプロジェクト生成済み"
else
  warn "iOSプロジェクトが未生成です"
  echo "  次: bash tool/prepare_ios.sh"
fi

if [[ -f ios/Runner.xcodeproj/project.pbxproj ]]; then
  bundle_id="$(grep 'PRODUCT_BUNDLE_IDENTIFIER = ' ios/Runner.xcodeproj/project.pbxproj | sed -E 's/.*PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);.*/\1/' | grep -v '\$(' | grep -v '\.RunnerTests$' | head -n 1 || true)"
  [[ -n "$bundle_id" ]] && ok "Bundle Identifier: $bundle_id" || warn "Bundle Identifierを確認できませんでした"

  team_id="$(grep 'DEVELOPMENT_TEAM = ' ios/Runner.xcodeproj/project.pbxproj | sed -E 's/.*DEVELOPMENT_TEAM = ([^;]*);.*/\1/' | grep -v '^$' | head -n 1 || true)"
  if [[ -n "$team_id" ]]; then
    ok "Signing Team設定済み: $team_id"
  else
    warn "Signing Teamが未設定です"
    echo "  次: open ios/Runner.xcworkspace"
    echo "      Runner > Signing & Capabilities"
    echo "      Automatically manage signing: ON"
    if [[ -n "$signing_team_candidate" ]]; then
      echo "      Team候補: $signing_team_candidate"
    else
      echo "      Team: Apple Account / Personal Team"
    fi
  fi
fi

echo
echo "--- iPhone接続 ---"
device_id=""
if command -v flutter >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
  device_id="$(flutter devices --machine 2>/dev/null | python3 -c '
import json, sys
try:
    items = json.load(sys.stdin)
except Exception:
    items = []
for item in items:
    target = str(item.get("targetPlatform", ""))
    if target.startswith("ios") and not item.get("emulator", False):
        print(item.get("id", ""))
        break
' 2>/dev/null || true)"
fi

if [[ -n "$device_id" ]]; then
  ok "Flutterが実機iPhoneを検出: $device_id"
else
  warn "Flutterでは実機iPhoneをまだ検出していません"

  devicectl_output=""
  if command -v xcrun >/dev/null 2>&1; then
    devicectl_output="$(xcrun devicectl list devices 2>/dev/null || true)"
  fi

  usb_iphone=""
  if command -v system_profiler >/dev/null 2>&1; then
    usb_iphone="$(system_profiler SPUSBDataType 2>/dev/null | grep -i -m 1 'iPhone' || true)"
  fi

  if [[ -n "$devicectl_output" && "$devicectl_output" == *"iPhone"* ]]; then
    if echo "$devicectl_output" | grep -Eqi 'unavailable|locked|developer[[:space:]]+mode'; then
      echo "  XcodeはiPhoneを認識していますが利用可能状態ではありません。"
      echo "  iPhoneをロック解除 → Macを信頼 → 設定 > プライバシーとセキュリティ > Developer Mode を確認してください。"
    else
      echo "  XcodeはiPhoneを認識しています。Flutter側だけ見えないため flutter doctor -v を確認してください。"
      echo "  Xcode > Window > Devices and Simulators で端末が利用可能かも確認してください。"
    fi
  elif [[ -n "$usb_iphone" ]]; then
    echo "  USBではiPhoneを検出していますが、Xcodeのデバイス一覧に出ていません。"
    echo "  iPhone側の「このコンピュータを信頼」を許可し、Developer Modeを確認してください。"
  else
    echo "  Mac側でiPhoneのUSB接続を確認できません。ケーブル・USBポート・ロック解除状態を確認してください。"
  fi
fi

echo
echo "=== 判定 ==="
if [[ "$errors" -gt 0 ]]; then
  echo "実機起動前に必須項目が $errors 件不足しています。"
  exit 1
fi
if [[ "$warnings" -gt 0 ]]; then
  echo "残りは上の △ を順番に解消してください。"
  exit 2
fi

echo "iPhone実機起動の準備が整っています。"
echo "次: bash tool/run_ios_device.sh"
