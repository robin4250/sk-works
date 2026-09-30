#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f ios/Runner/Info.plist || ! -f ios/Runner.xcodeproj/project.pbxproj ]]; then
  echo "✗ iOS project is not prepared"
  exit 1
fi

EXPECTED_BUNDLE_ID="${SKO_IOS_BUNDLE_ID:-com.robin4250.sko}"

python3 - "$EXPECTED_BUNDLE_ID" <<'PY'
from pathlib import Path
import plistlib
import sys

expected_bundle_id = sys.argv[1]

with Path("ios/Runner/Info.plist").open("rb") as f:
    data = plistlib.load(f)

required = [
    "CFBundleDisplayName",
    "NSFaceIDUsageDescription",
    "NSLocationWhenInUseUsageDescription",
    "NSCameraUsageDescription",
    "NSPhotoLibraryUsageDescription",
]
for key in required:
    if key not in data or not str(data[key]).strip():
        raise SystemExit(f"missing iOS plist contract: {key}")

if data.get("CFBundleDisplayName") != "SKO":
    raise SystemExit("unexpected CFBundleDisplayName")

if "NSLocationAlwaysUsageDescription" in data:
    raise SystemExit("Always location permission must not exist")
if "NSLocationAlwaysAndWhenInUseUsageDescription" in data:
    raise SystemExit("Always location permission must not exist")
if "location" in data.get("UIBackgroundModes", []):
    raise SystemExit("background location mode must not exist")

ats = data.get("NSAppTransportSecurity", {})
if ats.get("NSAllowsArbitraryLoads") is True:
    raise SystemExit("NSAllowsArbitraryLoads must not be enabled")
if ats.get("NSAllowsArbitraryLoadsInWebContent") is True:
    raise SystemExit("NSAllowsArbitraryLoadsInWebContent must not be enabled")

if data.get("UISupportedInterfaceOrientations") != [
    "UIInterfaceOrientationPortrait"
]:
    raise SystemExit("iPhone orientation contract must be portrait-only")

project = Path("ios/Runner.xcodeproj/project.pbxproj").read_text()
if f"PRODUCT_BUNDLE_IDENTIFIER = {expected_bundle_id};" not in project:
    raise SystemExit(f"unexpected Runner bundle identifier: expected {expected_bundle_id}")

scheme_path = Path("ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme")
if not scheme_path.exists():
    raise SystemExit("Runner.xcscheme is missing")
scheme = scheme_path.read_text()
launch_marker = '<LaunchAction'
launch_index = scheme.find(launch_marker)
if launch_index < 0:
    raise SystemExit("Runner LaunchAction is missing")
launch_tail = scheme[launch_index:launch_index + 800]
if 'buildConfiguration = "Release"' not in launch_tail:
    raise SystemExit("Xcode Run must use Release for standalone iPhone launch")
PY

echo "✓ iOS generated project contract"
