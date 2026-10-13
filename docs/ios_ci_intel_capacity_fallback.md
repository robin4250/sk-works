# iOS CI Intel capacity fallback

The hosted iOS check 113406853893 failed before a runner acquired the job.
Its GitHub annotations report hosted-runner acquisition failure and macOS arm64
capacity constraints. This change selects `macos-26-intel` and explicitly uses
`/Applications/Xcode_26.6.app/Contents/Developer`; it does not suppress build errors
or guarantee runner availability.

The workflow retains Flutter 3.47.5, analysis, all Flutter tests, both Debug and
Release unsigned iPhoneOS builds, lockfile checks, permissions, and secret checks.
It records CPU, macOS, actual Xcode, and iPhoneOS SDK versions and rejects an
unexpected CPU or Xcode version. Platform preparation includes the #766 fixes
that preserve the committed dependency lock during Flutter project generation.

## Environment boundary

CI is Intel macOS 26 / Xcode 26.6. The user's Mac remains Flutter 3.47.5 /
Xcode 27.0 with iOS deployment target 15.5. No device setup or installation
instructions are changed. Intel CI success does not establish Xcode 27 parity,
signing, TestFlight upload, or physical-device verification. User device
installation remains Release only; Debug here is a compile check without signing
or device installation.

Apple lists iOS 15 among the deployment targets for both Xcode 26.6 and Xcode 27.
The SDK version and minimum deployment target are separate. Flutter's 3.47
installation documentation still provides Intel SDK support (deprecated for a
future release); physical iOS compilation targets iPhoneOS rather than the host
CPU. Actual compatibility of this application's plugins and Flutter 3.47.5 must
be established by the complete CI run. No local macOS build was available for
this change.

## Official sources checked on 2026-10-08

- [GitHub hosted runner labels and CPU](https://docs.github.com/en/actions/reference/runners/github-hosted-runners): `macos-26-intel` and `macos-15-intel` are Intel; `macos-latest` is arm64.
- [macOS 26 Intel image](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md): Xcode 26.6 default and the explicit application path.
- [macOS 15 Intel image](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md): Xcode 16.4 default, with Xcode 26.3 available; not the selected fallback.
- [Xcode 27 arm64 image](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md): dedicated public-preview image; not equivalent to the Intel image.
- [Apple Xcode system requirements](https://developer.apple.com/xcode/system-requirements): supported macOS, SDKs, and deployment targets.
- [Flutter manual installation](https://docs.flutter.dev/install/manual): Flutter 3.47 Intel host support and future deprecation.
- [Flutter iOS build implementation](https://github.com/flutter/flutter/blob/master/packages/flutter_tools/lib/src/ios/mac.dart): physical-device SDK/destination and architecture selection. This moving source describes the mechanism, not a substitute for testing the pinned 3.47.5 release.

Local validation checks workflow structure, retention of all existing steps,
shell syntax, and whitespace. Hosted compilation remains pending until this
branch is published and its CI succeeds.
