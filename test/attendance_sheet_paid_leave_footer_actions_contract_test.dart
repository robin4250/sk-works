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
    expect(page, contains('_weekIndexContaining(_month, initial)'));
    expect(page, contains('if (!mounted) return;\n    SkoScrollChromeController.visible.value = true;'));
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


  test('attendance correction explains the four-step flow', () {
    final page = File(
      'lib/features/attendance/bulk_attendance_correction_page.dart',
    ).readAsStringSync();

    expect(page, contains('勤務修正の進め方'));
    expect(page, contains('① 月を選ぶ'));
    expect(page, contains('② 修正したい日を選ぶ'));
    expect(page, contains('③「修正」から内容を直す'));
    expect(page, contains('④ 最後にまとめてサイン'));
    expect(page, contains("label: const Text('修正')"));
    expect(page, contains('selectedCount'));
    expect(page, contains('selectedChanged'));
  });

}
