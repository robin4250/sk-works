import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('attendance sheet exposes existing correction flow as 勤務修正', () {
    final source = File(
      'lib/features/attendance/worker_attendance_sheet_page.dart',
    ).readAsStringSync();

    expect(source, contains("import 'bulk_attendance_correction_page.dart';"));
    expect(source, contains('BulkAttendanceCorrectionPage'));
    expect(source, contains("'勤務修正'"));
    expect(source, isNot(contains("'一括修正'")));
  });
}
