import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('device runner never silently chooses among multiple iPhones', () {
    final source = File('tool/run_ios_device.sh').readAsStringSync();

    expect(source, contains('"iphone" in str(item.get("name", "")).lower()'));
    expect(source, contains('複数の実機iPhoneを検出しました'));
    expect(source, contains('bash tool/device_day.sh <DEVICE_ID>'));
    expect(source, contains('NO_IPHONE'));
    expect(source, isNot(contains('break\n')));
  });
}
