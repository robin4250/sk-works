import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('device day refreshes iOS before generated contract checks', () {
    final day = File('tool/device_day.sh').readAsStringSync();
    final preflight = File('tool/device_day_preflight.sh').readAsStringSync();

    expect(
      day.indexOf('bash tool/prepare_ios.sh'),
      lessThan(day.indexOf('bash tool/device_day_preflight.sh')),
    );
    expect(
      preflight.indexOf('bash tool/prepare_ios.sh'),
      lessThan(preflight.indexOf('bash tool/check_ios_generated_contract.sh')),
    );
    expect(
      preflight,
      contains('detached HEADですが origin/main と同一コミット'),
    );
    expect(
      preflight,
      contains('Supabase REST reachable (HTTP 401: user認証前の応答)'),
    );
  });
}
