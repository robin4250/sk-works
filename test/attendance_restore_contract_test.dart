import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('attendance restore keeps today summary allowance and A4 contracts', () {
    final page = File(
      'lib/features/attendance/worker_attendance_sheet_page.dart',
    ).readAsStringSync();
    final pdf = File(
      'lib/features/attendance/attendance_pdf_service.dart',
    ).readAsStringSync();

    expect(page, contains('final isToday = date.year == now.year'));
    expect(page, contains('width: isToday ? 2.5 : 1'));
    expect(page, contains("allowanceUnits[name] ?? '回'"));
    expect(page, contains('allowanceCounts'));
    expect(page, contains('if (data.workedDays > 0)'));
    expect(page, contains('if (data.overtimeHours > 0)'));
    expect(page, contains('if (data.earlyHours > 0)'));
    expect(page, contains('if (data.nightHours > 0)'));
    expect(page, contains('day.overtimeHours'));
    expect(page, contains('day.earlyHours'));
    expect(page, contains('day.hasAllowance'));
    expect(pdf, contains('day.hasAllowance'));
    expect(pdf, contains('day.allowanceNames'));
    expect(pdf, contains("data.allowanceUnits[entry.key] ?? '回'"));
  });
}
