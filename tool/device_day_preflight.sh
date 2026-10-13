#!/usr/bin/env bash
set -u

echo "=== SKO device-day preflight ==="
echo

errors=0
warnings=0
ok() { echo "✓ $1"; }
warn() { echo "△ $1"; warnings=$((warnings + 1)); }
fail() { echo "✗ $1"; errors=$((errors + 1)); }

if [[ "$(uname -s)" != "Darwin" ]]; then
  fail "このスクリプトはMac用です"
  exit 1
fi

if [[ -f "tool/local_supabase_env.sh" ]]; then
  source "tool/local_supabase_env.sh"
else
  fail "tool/local_supabase_env.sh がありません"
  echo "  次: bash tool/mac_first_run.sh"
fi

echo "--- Git / main freshness ---"
if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch_name="$(git branch --show-current 2>/dev/null || true)"
  head_sha="$(git rev-parse --short HEAD 2>/dev/null || true)"
  [[ -n "$branch_name" ]] && ok "Git branch: $branch_name @ $head_sha"

  if git remote get-url origin >/dev/null 2>&1; then
    if git fetch --quiet origin main 2>/dev/null; then
      local_full="$(git rev-parse HEAD)"
      remote_full="$(git rev-parse FETCH_HEAD)"
      if [[ "$local_full" == "$remote_full" ]]; then
        if [[ "$branch_name" == "main" ]]; then
          ok "Git branch: main @ $head_sha"
        elif [[ -z "$branch_name" ]]; then
          ok "detached HEADですが 取得したmainと同一コミット: $head_sha"
        else
          warn "branchは $branch_name ですがHEADは 取得したmainと同一です"
        fi
        ok "ローカルHEADは取得したmainと一致"
      elif git merge-base --is-ancestor "$local_full" "$remote_full" 2>/dev/null; then
        fail "ローカルmainが取得したmainより古いです"
        echo "  作業差分が無いことを確認してから: git pull --ff-only origin main"
      else
        fail "ローカルHEADと取得したmainが分岐しています"
        echo "  自動pullや強制更新は行いません。git status / git logを確認してください"
        echo "  実機テストは取得したmainと一致するmainから実行してください"
      fi
    else
      warn "origin/mainの最新状態を取得できませんでした（ネットワークを確認）"
    fi
  fi
else
  fail "Gitリポジトリを確認できません"
fi

echo
echo "--- Flutter version ---"
if command -v flutter >/dev/null 2>&1; then
  flutter_version="$(flutter --version 2>&1 | sed -nE 's/.*Flutter[[:space:]]+([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' | head -n 1)"
  if [[ "$flutter_version" == "3.47.5" ]]; then
    ok "Flutter 3.47.5"
  else
    warn "Flutter $flutter_version（CI基準は3.47.5）"
  fi
else
  fail "Flutter が見つかりません"
fi

echo
echo "--- Supabase connectivity ---"
if ! command -v curl >/dev/null 2>&1; then
  fail "curl が見つかりません"
elif [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_PUBLISHABLE_KEY:-}" ]]; then
  fail "Supabase接続値が未設定です"
else
  auth_code="$(curl -sS -o /dev/null -w "%{http_code}" \
    -H "apikey: $SUPABASE_PUBLISHABLE_KEY" \
    "$SUPABASE_URL/auth/v1/health" 2>/dev/null || true)"
  if [[ "$auth_code" == "200" ]]; then
    ok "Supabase Auth reachable"
  else
    fail "Supabase Authへ接続できません (HTTP ${auth_code:-none})"
  fi

  rest_code="$(curl -sS -o /dev/null -w "%{http_code}" \
    -H "apikey: $SUPABASE_PUBLISHABLE_KEY" \
    "$SUPABASE_URL/rest/v1/" 2>/dev/null || true)"
  if [[ "$rest_code" == "200" ]]; then
    ok "Supabase REST reachable"
  elif [[ "$rest_code" == "401" ]]; then
    ok "Supabase REST reachable (HTTP 401: user認証前の応答)"
  else
    fail "Supabase RESTへ接続できません (HTTP ${rest_code:-none})"
  fi
fi

echo
echo "--- unsigned iOS release build ---"
if command -v flutter >/dev/null 2>&1; then
  if bash tool/prepare_ios.sh; then
    ok "最新iOS生成設定を再適用"
  else
    fail "iOSプロジェクト準備に失敗しました"
  fi

  if [[ -d ios/Runner.xcworkspace ]]; then
    if bash tool/check_ios_generated_contract.sh; then
      ok "iOS生成設定契約"
    else
      fail "iOS生成設定契約に違反があります"
    fi

    if flutter build ios --release --no-codesign; then
      ok "iOS release build（署名なし）"
      if [[ -f ios/Podfile.lock ]]; then
        ok "CocoaPods lockfile 生成済み"
      else
        warn "iOSビルドは成功しましたが Podfile.lock を確認できません"
      fi
    else
      fail "iOS release build（署名なし）に失敗しました"
      echo "  次: bash tool/collect_ios_diagnostics.sh"
    fi
  fi
else
  fail "Flutter がないためiOSビルドを確認できません"
fi

echo
echo "--- iPhone install readiness ---"
if bash tool/ios_install_assistant.sh; then
  ok "iPhone install assistant"
else
  rc=$?
  if [[ "$rc" -eq 2 ]]; then
    warn "実機固有の項目が残っています"
  else
    fail "実機起動の必須条件が不足しています"
  fi
fi

echo
echo "=== 判定 ==="
if [[ "$errors" -gt 0 ]]; then
  echo "実機起動前に必須項目が $errors 件あります。"
  echo "必要なら: bash tool/collect_ios_diagnostics.sh"
  exit 1
fi
if [[ "$warnings" -gt 0 ]]; then
  echo "基本準備は完了していますが、△ が $warnings 件あります。"
  exit 2
fi

echo "実機起動の準備が整っています。"
echo "次: bash tool/run_ios_device.sh"
