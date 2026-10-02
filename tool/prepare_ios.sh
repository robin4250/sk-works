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

BUNDLE_ID="com.skworks.skWorks"
if [[ -n "${SKO_IOS_BUNDLE_ID:-}" && "${SKO_IOS_BUNDLE_ID}" != "$BUNDLE_ID" ]]; then
  echo "注意: SKO_IOS_BUNDLE_ID=${SKO_IOS_BUNDLE_ID} は無視します。元SKOのBundle ID $BUNDLE_ID を使用します。"
fi

if [[ ! "$BUNDLE_ID" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]]; then
  echo "SKO_IOS_BUNDLE_ID が不正です: $BUNDLE_ID"
  echo "例: com.skworks.skWorks"
  exit 1
fi

if [[ -d ios/Runner.xcworkspace && -f ios/Runner.xcodeproj/project.pbxproj ]]; then
  echo "既存のiOSプロジェクトを再利用します。Signing Team設定を保持します。"
else
  echo "iOSプロジェクトを新規生成します..."
  flutter create . --platforms=ios --project-name sk_works --org com.skworks
fi

flutter pub get


APPICON_DIR="ios/Runner/Assets.xcassets/AppIcon.appiconset"
if [[ ! -d "$APPICON_DIR" || ! -f "$APPICON_DIR/Contents.json" ]]; then
  echo "AppIcon asset catalog が見つかりません: $APPICON_DIR"
  exit 1
fi
if ! command -v xcrun >/dev/null 2>&1 || ! command -v sips >/dev/null 2>&1; then
  echo "SKOアイコン生成に必要なXcode/sipsが見つかりません。"
  exit 1
fi

ICON_SOURCE="$APPICON_DIR/SKO-AppIcon-1024.png"
xcrun swift tool/generate_ios_app_icon.swift "$ICON_SOURCE"

python3 - "$APPICON_DIR" "$ICON_SOURCE" <<'PY'
from pathlib import Path
import json
import subprocess
import sys

appicon_dir = Path(sys.argv[1])
source = Path(sys.argv[2])
contents_path = appicon_dir / "Contents.json"
contents = json.loads(contents_path.read_text())

generated = 0
for entry in contents.get("images", []):
    filename = entry.get("filename")
    size = entry.get("size")
    scale = entry.get("scale")
    if not filename or not size or not scale:
        continue
    try:
        points = float(str(size).split("x", 1)[0])
        factor = float(str(scale).rstrip("x"))
        pixels = round(points * factor)
    except ValueError:
        continue
    target = appicon_dir / filename
    subprocess.run(
        ["sips", "-z", str(pixels), str(pixels), str(source), "--out", str(target)],
        check=True,
        stdout=subprocess.DEVNULL,
    )
    generated += 1

if generated < 10:
    raise SystemExit(f"AppIcon generation incomplete: {generated} files")
print(f"SKO AppIconを{generated}サイズ生成しました。")
PY

python3 - "$BUNDLE_ID" <<'PY'
from pathlib import Path
import plistlib
import re
import sys

bundle_id = sys.argv[1]
ios_min_version = "15.5"

podfile_path = Path("ios/Podfile")
podfile = podfile_path.read_text()

platform_pattern = re.compile(
    r"(?m)^\s*#?\s*platform\s+:ios,\s*['\"][^'\"]+['\"]\s*$"
)
if platform_pattern.search(podfile):
    podfile = platform_pattern.sub(
        "platform :ios, '" + ios_min_version + "'",
        podfile,
        count=1,
    )
else:
    podfile = "platform :ios, '" + ios_min_version + "'\n\n" + podfile

japanese_pod = "  pod 'GoogleMLKit/TextRecognitionJapanese', '~> 9.0.0'"
runner_marker = "target 'Runner' do\n"
if "GoogleMLKit/TextRecognitionJapanese" not in podfile:
    if runner_marker not in podfile:
        raise SystemExit("Podfile Runner target not found")
    podfile = podfile.replace(
        runner_marker,
        runner_marker + japanese_pod + "\n",
        1,
    )

flutter_settings = "    flutter_additional_ios_build_settings(target)\n"
mlkit_settings = (
    "    target.build_configurations.each do |config|\n"
    "      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.5'\n"
    "      config.build_settings['EXCLUDED_ARCHS[sdk=*]'] = 'armv7'\n"
    "    end\n"
)
if "EXCLUDED_ARCHS[sdk=*]" not in podfile:
    if flutter_settings not in podfile:
        raise SystemExit("Podfile flutter iOS settings hook not found")
    podfile = podfile.replace(
        flutter_settings,
        flutter_settings + mlkit_settings,
        1,
    )

podfile_path.write_text(podfile)

launch_storyboard_path = Path("ios/Runner/Base.lproj/LaunchScreen.storyboard")
launch_storyboard_path.parent.mkdir(parents=True, exist_ok=True)
launch_storyboard_path.write_text("""<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="21701" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" launchScreen="YES" useTraitCollections="YES" useSafeAreas="YES" colorMatched="YES">
    <device id="retina6_12" orientation="portrait" appearance="light"/>
    <dependencies>
        <deployment identifier="iOS"/>
        <plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="21679"/>
        <capability name="Safe area layout guides" minToolsVersion="9.0"/>
        <capability name="System colors in document resources" minToolsVersion="11.0"/>
        <capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
    </dependencies>
    <scenes>
        <scene sceneID="EHf-IW-A2E">
            <objects>
                <viewController id="01J-lp-oVM" sceneMemberID="viewController">
                    <view key="view" contentMode="scaleToFill" id="Ze5-6b-2t3">
                        <rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
                        <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
                        <subviews>
                            <label opaque="NO" userInteractionEnabled="NO" contentMode="left" text="SKO" textAlignment="center" translatesAutoresizingMaskIntoConstraints="NO" id="sko-launch-title">
                                <fontDescription key="fontDescription" type="system" weight="semibold" pointSize="30"/>
                                <color key="textColor" red="0.08" green="0.08" blue="0.08" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>
                            </label>
                        </subviews>
                        <viewLayoutGuide key="safeArea" id="Bcu-3y-fUS"/>
                        <color key="backgroundColor" red="1" green="1" blue="1" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>
                        <constraints>
                            <constraint firstItem="sko-launch-title" firstAttribute="centerX" secondItem="Ze5-6b-2t3" secondAttribute="centerX" id="sko-center-x"/>
                            <constraint firstItem="sko-launch-title" firstAttribute="centerY" secondItem="Ze5-6b-2t3" secondAttribute="centerY" id="sko-center-y"/>
                        </constraints>
                    </view>
                </viewController>
                <placeholder placeholderIdentifier="IBFirstResponder" id="iYj-Kq-Ea1" userLabel="First Responder" sceneMemberID="firstResponder"/>
            </objects>
            <point key="canvasLocation" x="52" y="374"/>
        </scene>
    </scenes>
</document>
""")

plist_path = Path("ios/Runner/Info.plist")
with plist_path.open("rb") as f:
    data = plistlib.load(f)

entries = {
    "CFBundleDisplayName": "SKO",
    "CFBundleName": "SKO",
    "NSFaceIDUsageDescription": "SKOの請求書や管理者用データなど重要情報を保護するため、Face IDを使用します。",
    "NSLocationWhenInUseUsageDescription": "SKOで出勤・退勤を登録する際、現場付近にいることを確認するため位置情報を使用します。GPS自動出勤を使わない場合はバックグラウンドで位置取得しません。",
    "NSLocationAlwaysAndWhenInUseUsageDescription": "GPS自動出勤を本人が有効にした場合、指定した曜日と時刻の前後に現場付近にいるか確認するため、バックグラウンドでも位置情報を使用します。",
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

# GPS automatic attendance uses background location only after the user
# explicitly enables that feature. The app does not start background location
# updates for normal manual / photo attendance.
background_modes = data.get("UIBackgroundModes")
if not isinstance(background_modes, list):
    background_modes = []
if "location" not in background_modes:
    background_modes.append("location")
data["UIBackgroundModes"] = background_modes

# SKO uses HTTPS endpoints. Never carry over a broad ATS bypass from an
# older/reused Xcode project.
ats = data.get("NSAppTransportSecurity")
if isinstance(ats, dict):
    ats.pop("NSAllowsArbitraryLoads", None)
    ats.pop("NSAllowsArbitraryLoadsInWebContent", None)
    if ats:
        data["NSAppTransportSecurity"] = ats
    else:
        data.pop("NSAppTransportSecurity", None)

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

project = pattern.sub(replace_bundle, project)
project = re.sub(
    r"(IPHONEOS_DEPLOYMENT_TARGET = )[^;]+(;)",
    r"\g<1>15.5\2",
    project,
)
project_path.write_text(project)

scheme_path = Path("ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme")
if scheme_path.exists():
    scheme = scheme_path.read_text()
    scheme = re.sub(
        r'(<LaunchAction\b[\s\S]*?buildConfiguration = ")[^"]+(")',
        r'\1Release\2',
        scheme,
        count=1,
    )
    scheme_path.write_text(scheme)
    print("XcodeのRun構成をReleaseに設定しました（単体起動用）。")

print("Info.plist に iOS 権限説明とGPS自動出勤用Background Locationを追加しました。")
print(f"Bundle Identifier を {bundle_id} に設定しました。")
print("iOS Deployment Target 15.5 / 日本語OCRモデルを設定しました。")
print("起動画面を固定レイアウトへ設定しました（アイコン全画面拡大なし）。")
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
echo "※ Xcodeの▶︎ RunもRelease構成です。Debug/Hot Reloadは bash tool/run_ios_device_debug.sh"
