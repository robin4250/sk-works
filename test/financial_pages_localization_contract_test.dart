import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('financial pages use language controller for visible UI', () {
    final files = [
      'lib/features/payroll/payroll_review_page.dart',
      'lib/features/payroll/payroll_statements_page.dart',
      'lib/features/payroll/payment_certificates_page.dart',
      'lib/features/invoices/invoice_cloud_page.dart',
    ];

    for (final path in files) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        contains('SkoLanguageController'),
        reason: path,
      );
    }

    final payroll =
        File('lib/features/payroll/payroll_review_page.dart').readAsStringSync();
    expect(
      payroll,
      contains("SkoLanguageController.tr('サブ管理者に見せない従業員')"),
    );

    final statements = File(
      'lib/features/payroll/payroll_statements_page.dart',
    ).readAsStringSync();
    expect(
      statements,
      contains("SkoLanguageController.tr('差引支給額')"),
    );
    expect(
      statements,
      contains('SkoLanguageController.tr(entry.key)'),
    );

    final certificates = File(
      'lib/features/payroll/payment_certificates_page.dart',
    ).readAsStringSync();
    expect(
      certificates,
      contains("SkoLanguageController.tr('支払証明書')"),
    );

    final invoices =
        File('lib/features/invoices/invoice_cloud_page.dart').readAsStringSync();
    expect(
      invoices,
      contains("SkoLanguageController.tr('請求書プレビュー')"),
    );
  });

  test('English language pack covers financial pages', () {
    final english = File(
      'lib/international/languages/en/english_language_pack.dart',
    ).readAsStringSync();

    for (final key in [
      '給料一覧',
      'サブ管理者に見せない従業員',
      '給与明細はまだ発行されていません',
      '差引支給額',
      '総支給額',
      '控除額',
      '支払証明書',
      '支払証明書設定',
      '請求書設定',
      '請求書プレビュー',
      'この期間の請求書はありません',
      '請求合計',
    ]) {
      expect(english, contains("'$key':"), reason: key);
    }
  });

  test('financial month labels have an explicit English branch', () {
    final review =
        File('lib/features/payroll/payroll_review_page.dart').readAsStringSync();
    final statements = File(
      'lib/features/payroll/payroll_statements_page.dart',
    ).readAsStringSync();
    final certificates = File(
      'lib/features/payroll/payment_certificates_page.dart',
    ).readAsStringSync();
    final invoices =
        File('lib/features/invoices/invoice_cloud_page.dart').readAsStringSync();

    for (final source in [review, statements, certificates, invoices]) {
      expect(source, contains('SkoLanguageController.isEnglish'));
    }
  });
}
