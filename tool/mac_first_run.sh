#!/usr/bin/env bash
set -u

echo "=== SKO Mac first-run assistant ==="
echo

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "✗ このスクリプトはMac用です。"
  exit 1
fi

errors=0
warnings=0

ok() { echo "✓ $1"; }
warn() { echo "△ $1"; warnings=$((warnings + 1)); }
fail() { echo "✗ $1"; errors=$((errors + 1)); }

check_cmd() {
  local label="$1"
  local cmd="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "$label"
  else
    fail "$label が見つかりません"
  fi
}

echo "--- Mac / Xcode ---"
if command -v xcodebuild >/dev/null 2>&1; then
  ok "Xcode command line tools"
  xcodebuild -version || true
  if xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
    ok "Xcode初回セットアップ完了"
  else
    warn "Xcodeの追加コンポーネントまたは初回セットアップが必要です"
    echo "  次: Xcodeを一度起動して案内を完了してください"
    echo "  または必要に応じて: sudo xcodebuild -runFirstLaunch"
  fi
else
  fail "Xcode command line tools が見つかりません"
  echo "  次: App StoreからXcodeをインストールし、一度起動してください"
fi

echo
echo "--- 必須ツール ---"
check_cmd "Git" git
check_cmd "Flutter" flutter
check_cmd "Python 3" python3
check_cmd "CocoaPods" pod

if ! command -v flutter >/dev/null 2>&1; then
  echo "  Flutter SDKをインストール後、flutter doctor を実行してください"
fi

if ! command -v pod >/dev/null 2>&1; then
  echo "  CocoaPodsをインストール後、再実行してください"
fi

echo
echo "--- SKOローカル設定 ---"
if [[ -f "tool/local_supabase_env.sh" ]]; then
  ok "tool/local_supabase_env.sh"
  source "tool/local_supabase_env.sh"
else
  if [[ -f "tool/local_supabase_env.example.sh" ]]; then
    cp tool/local_supabase_env.example.sh tool/local_supabase_env.sh
    warn "Supabase設定ファイルを作成しました"
    echo "  次: tool/local_supabase_env.sh を開き、実際のSUPABASE_URLとSUPABASE_PUBLISHABLE_KEYを入力してください"
  else
    fail "Supabase設定テンプレートが見つかりません"
  fi
fi

if [[ -n "${SUPABASE_URL:-}" && "${SUPABASE_URL}" != *"YOUR_PROJECT_REF"* ]]; then
  ok "SUPABASE_URL 設定済み"
else
  warn "SUPABASE_URL は実値の設定が必要です"
fi

if [[ -n "${SUPABASE_PUBLISHABLE_KEY:-}" && "${SUPABASE_PUBLISHABLE_KEY}" != "YOUR_PUBLISHABLE_KEY" ]]; then
  ok "SUPABASE_PUBLISHABLE_KEY 設定済み"
else
  warn "SUPABASE_PUBLISHABLE_KEY は実値の設定が必要です"
fi

echo
echo "--- iOSプロジェクト ---"
if [[ -d ios/Runner.xcworkspace ]]; then
  ok "iOSプロジェクト生成済み"
else
  if command -v flutter >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    echo "iOSプロジェクトを生成します..."
    if bash tool/prepare_ios.sh; then
      ok "iOSプロジェクト生成完了"
    else
      fail "iOSプロジェクト生成に失敗しました"
    fi
  else
    warn "必須ツールが揃った後に bash tool/prepare_ios.sh を実行してください"
  fi
fi

echo
echo "--- 次の段階 ---"
if [[ "$errors" -gt 0 ]]; then
  echo "必須項目が $errors 件不足しています。上の ✗ を解消して同じスクリプトを再実行してください。"
  exit 1
fi

if [[ "$warnings" -gt 0 ]]; then
  echo "基本準備は進んでいます。上の △ を解消した後、次を実行してください:"
  echo "  bash tool/ios_install_assistant.sh"
  exit 2
fi

echo "Mac側の基本準備は完了しています。"
echo "次:"
echo "  bash tool/ios_install_assistant.sh"
