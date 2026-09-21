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
PY

echo "✓ iOS generated project contract"
