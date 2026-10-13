import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('approvals hub primary labels are localized', () {
    final approvals =
        File('lib/features/approvals/approvals_hub_page.dart').readAsStringSync();

    expect(approvals, contains("SkoLanguageController.tr('承認待ち')"));
    expect(approvals, contains("SkoLanguageController.tr('日報の承認待ち')"));
    expect(approvals, contains("SkoLanguageController.tr('勤務修正の承認待ち')"));
    expect(approvals, contains("SkoLanguageController.tr('有給申請の承認待ち')"));
  });

  test('attendance management primary labels are localized', () {
    final management = File(
      'lib/features/attendance/attendance_management_page.dart',
    ).readAsStringSync();

    expect(management, contains("SkoLanguageController.tr('勤怠管理')"));
    expect(management, contains("SkoLanguageController.tr('個別')"));
    expect(management, contains("SkoLanguageController.tr('一括')"));
  });

  test('English pack covers approvals and attendance management labels', () {
    final english = File(
      'lib/international/languages/en/english_language_pack.dart',
    ).readAsStringSync();

    for (final key in [
      '日報の承認待ち',
      '勤務修正の承認待ち',
      '有給申請の承認待ち',
      '従業員の本登録承認',
      '勤怠管理',
      '一括',
    ]) {
      expect(english, contains("'$key':"));
    }
  });
}
