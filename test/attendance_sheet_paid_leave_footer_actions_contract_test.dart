import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('attendance sheet renders paid leave before ordinary rest labels', () {
    final page = File(
      'lib/features/attendance/worker_attendance_sheet_page.dart',
    ).readAsStringSync();
    final pdf = File(
      'lib/features/attendance/attendance_pdf_service.dart',
    ).readAsStringSync();

    expect(page, contains("day.paidLeave"));
    expect(page, contains("SkoLanguageController.tr('有給')"));
    expect(pdf, contains("day.paidLeave"));
    expect(pdf, contains("SkoLanguageController.tr('有給')"));
  });

  test('returning from month calendar restores shared footer chrome', () {
    final page = File(
      'lib/features/attendance/worker_attendance_sheet_page.dart',
    ).readAsStringSync();

    expect(page, contains("import '../../widgets/sko_scroll_chrome.dart';"));
    expect(page, contains('SkoScrollChromeController.visible.value = true;'));
  });

  test('paid leave and correction actions are obvious buttons', () {
    final page = File(
      'lib/features/attendance/worker_attendance_sheet_page.dart',
    ).readAsStringSync();

    expect(page, contains('FilledButton.tonalIcon'));
    expect(page, contains("SkoLanguageController.tr('有給申請')"));
    expect(page, contains("SkoLanguageController.tr('勤務修正')"));
    expect(page, contains('Icons.event_available_outlined'));
    expect(page, contains('Icons.edit_calendar_outlined'));
  });

  test('off to paid leave correction is an obvious button', () {
    final page = File(
      'lib/features/attendance/bulk_attendance_correction_page.dart',
    ).readAsStringSync();

    expect(page, contains('FilledButton.tonalIcon'));
    expect(page, contains("const Text(\n                    '休み → 有給'"));
    expect(page, contains('Icons.event_repeat_outlined'));
  });

}
