#!/usr/bin/env bash
set -euo pipefail

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter が見つかりません。先に Flutter SDK をインストールしてください。"
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 が見つかりません。Xcode Command Line Tools または Python 3 を準備してください。"
  exit 1
fi

BUNDLE_ID="${SKO_IOS_BUNDLE_ID:-com.robin4250.sko}"

if [[ ! "$BUNDLE_ID" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]]; then
  echo "SKO_IOS_BUNDLE_ID が不正です: $BUNDLE_ID"
  echo "例: com.robin4250.sko"
  exit 1
fi

if [[ -d ios/Runner.xcworkspace && -f ios/Runner.xcodeproj/project.pbxproj ]]; then
  echo "既存のiOSプロジェクトを再利用します。Signing Team設定を保持します。"
else
  echo "iOSプロジェクトを新規生成します..."
  flutter create . --platforms=ios --project-name sk_works --org com.skworks
fi

flutter pub get

python3 - "$BUNDLE_ID" <<'PY'
from pathlib import Path
import plistlib
import re
import sys

bundle_id = sys.argv[1]

plist_path = Path("ios/Runner/Info.plist")
with plist_path.open("rb") as f:
    data = plistlib.load(f)

entries = {
    "CFBundleDisplayName": "SKO",
    "CFBundleName": "SKO",
    "NSFaceIDUsageDescription": "SKOの請求書や管理者用データなど重要情報を保護するため、Face IDを使用します。",
    "NSLocationWhenInUseUsageDescription": "SKOで出勤・退勤を登録する際、現場付近にいることを確認するため位置情報を使用します。常時追跡は行いません。",
    "NSCameraUsageDescription": "SKOで出勤確認や資格証、現場写真を登録するためカメラを使用します。",
    "NSPhotoLibraryUsageDescription": "SKOでプロフィール写真や現場・チャットの写真を選択するため写真ライブラリを使用します。",
}

for key, value in entries.items():
    data[key] = value

# SKO's iPhone UI is designed and acceptance-tested in portrait.
# Keep the iPad-specific orientation key untouched.
data["UISupportedInterfaceOrientations"] = [
    "UIInterfaceOrientationPortrait",
]

# SKO never needs Always/background location. Remove stale keys if an
# existing Xcode project or plist carried them from an earlier experiment.
data.pop("NSLocationAlwaysUsageDescription", None)
data.pop("NSLocationAlwaysAndWhenInUseUsageDescription", None)

background_modes = data.get("UIBackgroundModes")
if isinstance(background_modes, list):
    filtered_modes = [mode for mode in background_modes if mode != "location"]
    if filtered_modes:
        data["UIBackgroundModes"] = filtered_modes
    else:
        data.pop("UIBackgroundModes", None)

with plist_path.open("wb") as f:
    plistlib.dump(data, f, fmt=plistlib.FMT_XML, sort_keys=False)

project_path = Path("ios/Runner.xcodeproj/project.pbxproj")
project = project_path.read_text()

pattern = re.compile(r"(PRODUCT_BUNDLE_IDENTIFIER = )([^;]+)(;)")

def replace_bundle(match):
    current = match.group(2).strip()
    if "$(" in current:
        return match.group(0)
    if current.endswith(".RunnerTests"):
        return f"{match.group(1)}{bundle_id}.RunnerTests{match.group(3)}"
    return f"{match.group(1)}{bundle_id}{match.group(3)}"

project_path.write_text(pattern.sub(replace_bundle, project))

print("Info.plist に iOS 権限説明を追加しました。")
print(f"Bundle Identifier を {bundle_id} に設定しました。")
PY

echo
echo "iOS準備完了。次は:"
echo "1. open ios/Runner.xcworkspace"
echo "2. Runner > Signing & Capabilities で Apple Account / Personal Team を選択"
echo "3. Automatically manage signing を ON"
echo "4. Bundle Identifier: $BUNDLE_ID"
echo "5. iPhoneをUSB接続して信頼"
echo "6. bash tool/ios_install_assistant.sh"
echo "7. bash tool/run_ios_device.sh"
