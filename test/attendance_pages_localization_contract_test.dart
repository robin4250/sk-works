import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('today attendance and management primary labels are localized', () {
    final today = File(
      'lib/features/attendance/today_attendance_page.dart',
    ).readAsStringSync();
    final management = File(
      'lib/features/attendance/attendance_management_page.dart',
    ).readAsStringSync();

    expect(today, contains("SkoLanguageController.tr('本日の出勤')"));
    expect(today, contains("SkoLanguageController.tr('再読み込み')"));
    expect(management, contains("SkoLanguageController.tr('勤怠管理')"));
    expect(management, contains("SkoLanguageController.tr('個別')"));
    expect(management, contains("SkoLanguageController.tr('一括')"));
  });
}
