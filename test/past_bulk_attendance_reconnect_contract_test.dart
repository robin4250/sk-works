import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('clock-in confirmation reconnects the existing past bulk attendance flow', () {
    final source = File(
      'lib/features/attendance/attendance_verification_page.dart',
    ).readAsStringSync();

    expect(source, contains("import 'bulk_attendance_page.dart';"));
    expect(source, contains('BulkAttendancePage(repository: repository)'));
    expect(source, contains('過去の出勤をまとめて登録する'));
    expect(source, contains('if (!isClockOut && _canManageAttendance)'));
    expect(source, contains('minimumSize: const Size.fromHeight(52)'));
  });
}
