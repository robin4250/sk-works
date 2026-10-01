import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('device-day preflight prevents stale main but allows detached origin/main', () {
    final source =
        File('tool/device_day_preflight.sh').readAsStringSync();

    expect(source, contains('git fetch --quiet origin main'));
    expect(source, contains('origin/main'));
    expect(source, contains('ローカルHEADは origin/main と一致'));
    expect(
      source,
      contains('detached HEADですが origin/main と同一コミット'),
    );
    expect(
      source,
      contains('ローカルmainがorigin/mainより古いです'),
    );
    expect(
      source,
      contains('ローカルHEADとorigin/mainが分岐しています'),
    );
    expect(
      source,
      contains('自動pullや強制更新は行いません'),
    );
    expect(
      source,
      isNot(contains('fail "現在のbranchは main ではありません')),
    );
  });
}
