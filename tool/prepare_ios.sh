#!/usr/bin/env bash
set -euo pipefail

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter が見つかりません。先に Flutter SDK をインストールしてください。"
  exit 1
fi

flutter create . --platforms=ios --project-name sk_works --org com.skworks
flutter pub get

PLIST="ios/Runner/Info.plist"

python3 - <<'PY'
from pathlib import Path
import plistlib

path = Path("ios/Runner/Info.plist")
with path.open("rb") as f:
    data = plistlib.load(f)

entries = {
    "NSFaceIDUsageDescription": "SKOの請求書や管理者用データなど重要情報を保護するため、Face IDを使用します。",
    "NSLocationWhenInUseUsageDescription": "SKOで出勤・退勤を登録する際、現場付近にいることを確認するため位置情報を使用します。常時追跡は行いません。",
    "NSCameraUsageDescription": "SKOで出勤確認や資格証、現場写真を登録するためカメラを使用します。",
    "NSPhotoLibraryUsageDescription": "SKOでプロフィール写真や現場・チャットの写真を選択するため写真ライブラリを使用します。",
}

for key, value in entries.items():
    data[key] = value

with path.open("wb") as f:
    plistlib.dump(data, f, fmt=plistlib.FMT_XML, sort_keys=False)

print("Info.plist に iOS 権限説明を追加しました。")
PY

echo
echo "iOS準備完了。次は:"
echo "1. open ios/Runner.xcworkspace"
echo "2. Runner > Signing & Capabilities で Apple Account / Personal Team を選択"
echo "3. Bundle Identifier が重複する場合は com.skworks.sko.<任意文字列> に変更"
echo "4. iPhoneをUSB接続して信頼"
echo "5. Xcodeで実機を選択してRun"
