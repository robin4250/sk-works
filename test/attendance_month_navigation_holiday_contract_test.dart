import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('monthly attendance calendar supports holiday red labels and month navigation', () {
    final page = File(
      'lib/features/attendance/worker_attendance_sheet_page.dart',
    ).readAsStringSync();

    expect(page, contains('final holidayName = JapanHoliday.name(date);'));
    expect(page, contains('isHoliday || date.weekday == DateTime.sunday'));
    expect(page, contains('color: Theme.of(context).colorScheme.error'));
    expect(page, contains("SkoLanguageController.tr('前の月')"));
    expect(page, contains("SkoLanguageController.tr('次の月')"));
    expect(page, contains('_changeMonth(-1)'));
    expect(page, contains('_changeMonth(1)'));
    expect(page, contains('repository.loadMonth('));
    expect(page, contains('workerId: widget.workerId'));
    expect(page, contains('holidayName'));
  });
}
