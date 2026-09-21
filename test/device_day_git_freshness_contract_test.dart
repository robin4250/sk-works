import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('device-day preflight prevents installing stale main', () {
    final source =
        File('tool/device_day_preflight.sh').readAsStringSync();

    expect(source, contains('git fetch --quiet origin main'));
    expect(source, contains('origin/main'));
    expect(source, contains('git pull --ff-only origin main'));
    expect(source, isNot(contains('git pull --ff-only origin main 2>/dev/null')));
    expect(source, contains('現在のbranchは main ではありません'));
    expect(source, contains('ローカルHEADとorigin/mainが分岐しています'));
    expect(source, contains('実機テストはorigin/mainと一致するmainから実行してください'));
    expect(source, contains('fail "現在のbranchは main ではありません'));
    expect(source, contains('fail "ローカルHEADとorigin/mainが分岐しています'));
    expect(source, contains('自動pullや強制更新は行いません'));
  });
}
