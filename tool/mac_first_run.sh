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

if command -v flutter >/dev/null 2>&1; then
  flutter_version="$(flutter --version 2>/dev/null | head -n 1 | awk '{print $2}')"
  if [[ "$flutter_version" == "3.47.5" ]]; then
    ok "Flutter 3.47.5（CIと一致）"
  else
    warn "Flutter $flutter_version を検出。CI基準は3.47.5です"
    echo "  実機テスト前にFlutter 3.47.5へ合わせることを推奨します"
  fi
else
  echo "  Flutter SDKをインストール後、flutter doctor を実行してください"
fi

if ! command -v pod >/dev/null 2>&1; then
  echo "  CocoaPodsをインストール後、再実行してください"
fi

echo
echo "--- Flutter依存固定 ---"
if command -v flutter >/dev/null 2>&1; then
  if flutter pub get; then
    ok "Flutter依存解決"
    if [[ -f "pubspec.lock" ]]; then
      ok "pubspec.lock 生成済み"
      if git check-ignore -q pubspec.lock 2>/dev/null; then
        fail "pubspec.lock が .gitignore に含まれています"
      else
        ok "pubspec.lock はGit管理可能"
      fi
      if git diff --quiet -- pubspec.lock; then
        ok "pubspec.lock は現在の固定依存と一致"
      else
        fail "flutter pub get により pubspec.lock が変更されました"
        echo "  依存固定が変わっているため、実機テスト前に差分を確認してください"
      fi
    else
      fail "flutter pub get 後も pubspec.lock が生成されませんでした"
    fi
  else
    fail "flutter pub get に失敗しました"
  fi
fi

echo
echo "--- SKOローカル設定 ---"
if [[ -f "tool/local_supabase_env.sh" ]]; then
  ok "tool/local_supabase_env.sh"
  source "tool/local_supabase_env.sh"
else
  if [[ -f "tool/local_supabase_env.example.sh" ]]; then
    cp tool/local_supabase_env.example.sh tool/local_supabase_env.sh
    source tool/local_supabase_env.sh
    ok "Supabase設定ファイルを公開クライアント設定から作成しました"
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
