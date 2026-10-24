#!/usr/bin/env python3
"""Validate tracked generation and optionally emit the exact Swift for SDK typecheck.

This is a source/generation check, not an iPhone delivery or race runtime test.
"""
import argparse
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--emit-swift', type=pathlib.Path)
args = parser.parse_args()
prepare = (ROOT / 'tool/prepare_ios.sh').read_text()
fragment = (ROOT / 'tool/ios/checkout_reminders.swift').read_text()
matches = re.findall(r"cat > ios/Runner/AppDelegate\.swift <<'SWIFT'\n(.*?)\nSWIFT", prepare, re.S)
assert len(matches) == 1, 'generated AppDelegate must be unambiguous'
app_delegate = matches[0]
assert 'import UserNotifications' in app_delegate
assert app_delegate.count('private var skoCheckoutReminders: SkoCheckoutReminders?') == 1
assert app_delegate.count('SkoCheckoutReminders(messenger: registrar.messenger())') == 1
assert 'sko.notification_settings' in app_delegate, 'existing notification settings bridge preserved'
assert 'GeneratedPluginRegistrant.register(with: self)' in app_delegate
assert 'super.application(application, didFinishLaunchingWithOptions: launchOptions)' in app_delegate
assert prepare.count('cat tool/ios/checkout_reminders.swift >> ios/Runner/AppDelegate.swift') == 1
assert 'removeAllPendingNotificationRequests' not in fragment
assert 'removeAllDeliveredNotifications' not in fragment
assert 'previous.userNotificationCenter?' in fragment
assert 'self.epoch == capturedEpoch' in fragment and 'self.revisions[source] == revision' in fragment
assert 'UUID().uuidString' in fragment, 'late cleanup must not delete a newer attempt identifier'
assert 'skoCheckoutSourceId' in fragment and 'content.userInfo = ["skoCheckoutSourceId": source]' in fragment
assert 'UNNotificationDefaultActionIdentifier' in fragment
assert 'consumePendingTap' in fragment and 'requestAuthorization' in fragment
assert 'repeats: false' in fragment and '8 * 24 * 60 * 60' in fragment
assert 'clock_out' not in fragment and 'save_daily_report' not in fragment
assert (app_delegate + fragment).count('final class SkoCheckoutReminders:') == 1
if args.emit_swift:
    # Frameworks are Apple's real SDK; only Flutter channel types are stubs.
    # CI separately builds the whole generated Flutter iOS application.
    header = '''import Foundation
import UserNotifications
protocol FlutterBinaryMessenger {}
typealias FlutterResult = (Any?) -> Void
let FlutterMethodNotImplemented = NSObject()
final class FlutterError: NSObject {
  init(code: String, message: String?, details: Any?) { super.init() }
}
final class FlutterMethodCall {
  let method: String = ""
  let arguments: Any? = nil
}
final class FlutterMethodChannel {
  init(name: String, binaryMessenger: FlutterBinaryMessenger) {}
  func setMethodCallHandler(_ handler: ((FlutterMethodCall, @escaping FlutterResult) -> Void)?) {}
  func invokeMethod(_ method: String, arguments: Any?, result: FlutterResult? = nil) {}
}
'''
    args.emit_swift.parent.mkdir(parents=True, exist_ok=True)
    args.emit_swift.write_text(header + fragment)
print('checkout native generation/source contract: 19 checks passed; device delivery unverified')
