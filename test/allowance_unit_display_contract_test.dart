import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/worker_attendance_sheet_repository.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  // Allowance editing moved to the payroll common entry. Its save/reload and
  // legacy-unit contracts are covered by company common payroll tests.
  test('attendance week month and pdf use saved allowance units', () {
    final sheet =
        read('lib/features/attendance/worker_attendance_sheet_page.dart');
    final repo =
        read('lib/features/attendance/worker_attendance_sheet_repository.dart');
    final pdf =
        read('lib/features/attendance/attendance_pdf_service.dart');

    expect(repo, contains("'my_attendance_allowance_units'"));
    expect(
      WorkerAttendanceDay(date: DateTime(2026, 10, 26),
        allowanceUnits: const {'自由記入手当': '時間'})
          .allowanceDisplayText('自由記入手当'),
      '自由記入手当1時間',
    );
    expect(sheet, contains("data.allowanceUnits[entry.key] ?? '回'"));
    expect(pdf, contains("data.allowanceUnits[entry.key] ?? '回'"));
  });
}

