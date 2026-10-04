import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('approvals hub and personal payroll use language controller', () {
    final approvals =
        File('lib/features/approvals/approvals_hub_page.dart').readAsStringSync();
    final payroll =
        File('lib/features/payroll/payroll_statements_page.dart').readAsStringSync();

    expect(approvals, contains("SkoLanguageController.tr('承認待ち')"));
    expect(approvals, contains("SkoLanguageController.tr('日報の承認待ち')"));
    expect(approvals, contains("SkoLanguageController.tr('勤務修正の承認待ち')"));
    expect(approvals, contains("SkoLanguageController.tr('有給申請の承認待ち')"));
    expect(payroll, contains("SkoLanguageController.tr('給与明細')"));
    expect(payroll, contains("SkoLanguageController.tr('確認済み')"));
    expect(payroll, contains("SkoLanguageController.tr('未確定')"));
    expect(payroll, contains("SkoLanguageController.tr('差引支給額')"));
    expect(payroll, contains("SkoLanguageController.tr('印刷')"));
  });

  test('English pack covers approvals and payroll statement labels', () {
    final english = File(
      'lib/international/languages/en/english_language_pack.dart',
    ).readAsStringSync();

    for (final key in [
      '日報の承認待ち',
      '勤務修正の承認待ち',
      '有給申請の承認待ち',
      '従業員の本登録承認',
      '給与明細を利用できません。',
      '給与明細はまだ発行されていません',
      '給 与 明 細',
      '総支給額',
      '控除額',
      '差引支給額',
      '内訳',
    ]) {
      expect(english, contains("'$key':"));
    }
  });
}
