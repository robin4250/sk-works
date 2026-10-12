#!/usr/bin/env bash
# Register weather credentials privately; never pass their values as CLI arguments.
set +x
set -euo pipefail
umask 077
readonly weather_project_ref='ztktgquxvcxcjxtluspu'
if ! command -v supabase >/dev/null 2>&1; then
  printf '%s\n' 'Supabase CLIが必要です。インストール後にこのコマンドを再実行してください。' >&2
  exit 1
fi
if [[ ! -r /dev/tty || ! -w /dev/tty ]]; then
  printf '%s\n' 'Macのターミナルで実行してください。APIキーをチャットへ貼らないでください。' >&2
  exit 1
fi
if ! supabase secrets list --project-ref "$weather_project_ref" >/dev/null 2>&1; then
  printf '%s\n' 'Supabaseのログインまたは対象プロジェクトへのアクセスが必要です。supabase login を実行後、再実行してください。' >&2
  exit 1
fi
weather_secret_dir=''
weather_terminal_state=$(stty -g < /dev/tty)
weather_cleanup() {
  stty "$weather_terminal_state" < /dev/tty 2>/dev/null || true
  if [[ -n "$weather_secret_dir" ]]; then rm -rf -- "$weather_secret_dir"; fi
}
trap weather_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
stty -echo < /dev/tty
printf '%s\n' 'SK WORKSの天気取得設定を登録します（入力したAPIキーは画面に表示されません）。' > /dev/tty
printf '%s' 'Google Geocoding / Time Zone APIキー: ' > /dev/tty
IFS= read -r -s weather_google_key < /dev/tty
printf '\n' > /dev/tty
printf '%s' 'OpenWeather One Call 3.0 APIキー: ' > /dev/tty
IFS= read -r -s weather_openweather_key < /dev/tty
printf '\n' > /dev/tty
if [[ ! "$weather_google_key" =~ ^[A-Za-z0-9_-]{16,}$ || ! "$weather_openweather_key" =~ ^[A-Za-z0-9_-]{16,}$ ]]; then
  printf '%s\n' 'APIキーの形式を確認してください。未登録です。' >&2
  unset weather_google_key weather_openweather_key
  exit 1
fi
weather_secret_dir=$(mktemp -d "${TMPDIR:-/tmp}/sko-weather-secrets.XXXXXX")
weather_env_file="$weather_secret_dir/weather.env"
printf 'WEATHER_GEOCODING_PROVIDER=google\nWEATHER_GEOCODING_API_KEY=%s\nOPENWEATHER_API_KEY=%s\n' "$weather_google_key" "$weather_openweather_key" > "$weather_env_file"
unset weather_google_key weather_openweather_key
if ! supabase secrets set --project-ref "$weather_project_ref" --env-file "$weather_env_file" > "$weather_secret_dir/cli-output" 2>&1; then
  printf '%s\n' '設定を登録できませんでした。Supabaseのログイン・権限・接続を確認してください。キーは表示しません。' >&2
  exit 1
fi
printf '%s\n' 'サーバー設定の登録が完了しました。ホームを更新して実際の天気取得を確認してください。'
