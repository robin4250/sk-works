import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('approval hub shows red count badges only for pending items', () {
    final source = File('lib/features/approvals/approvals_hub_page.dart').readAsStringSync();
    expect(source, contains('color: Colors.red'));
    expect(source, contains('else if (count > 0)'));
    expect(source, contains('_dailyCount'));
    expect(source, contains('_attendanceCount'));
    expect(source, contains('_paidLeaveCount'));
    expect(source, contains('_onboardingCount'));
    expect(source, contains('await _loadCounts()'));
  });
}
