import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
    expect(sheet, contains("day.allowanceUnits[name] ?? '回'"));
    expect(sheet, contains("data.allowanceUnits[entry.key] ?? '回'"));
    expect(pdf, contains("data.allowanceUnits[entry.key] ?? '回'"));
  });
}
