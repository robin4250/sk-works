import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('generated iOS notification bridge reads OS permission and opens only app settings', () {
    final prepare = File('tool/prepare_ios.sh').readAsStringSync();
    final start = prepare.indexOf(
      "cat > ios/Runner/AppDelegate.swift <<'SWIFT'",
    );
    final end = prepare.indexOf('\nSWIFT', start);
    final native = prepare.substring(start, end);
    expect(native, contains('import UserNotifications'));
    expect(
      native,
      contains('UNUserNotificationCenter.current().getNotificationSettings'),
    );
    expect(native, contains('settings.authorizationStatus'));
    expect(native, contains('UIApplication.openNotificationSettingsURLString'));
    expect(native, contains('UIApplication.openSettingsURLString'));
    expect(native, contains('if #available(iOS 16.0, *)'));
    expect(
      native.substring(
        native.indexOf('case "authorizationStatus":'),
        native.indexOf('case "openSettings":'),
      ),
      isNot(contains('requestAuthorization')),
    );
    expect(
      native,
      contains(
        'center.requestAuthorization(options: [.alert, .badge, .sound])',
      ),
    );
    expect(native, contains('settings.authorizationStatus == .notDetermined'));
    for (final channel in [
      'sko.notification_settings',
      'sko.capture_metadata',
      'sko.multi_pin_map',
    ]) {
      expect(
        RegExp(RegExp.escape('name: "$channel"')).allMatches(native),
        hasLength(1),
      );
    }
    expect(native, contains('case "photoCapturedAt":'));
    expect(native, contains('case "reverseGeocode":'));
  });
}
