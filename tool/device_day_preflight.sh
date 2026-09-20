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

echo "--- Flutter version ---"
if command -v flutter >/dev/null 2>&1; then
  flutter_version="$(flutter --version 2>/dev/null | head -n 1 | awk '{print $2}')"
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
  else
    fail "Supabase RESTへ接続できません (HTTP ${rest_code:-none})"
  fi
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
