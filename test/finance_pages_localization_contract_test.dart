import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('finance pages use language controller for primary labels', () {
    final paths = [
      'lib/features/payroll/payroll_statements_page.dart',
      'lib/features/payroll/payroll_review_page.dart',
      'lib/features/payroll/payment_certificates_page.dart',
    ];
    for (final path in paths) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        contains("international/language_controller.dart"),
        reason: path,
      );
    }

    final statements =
        File(paths[0]).readAsStringSync();
    final review =
        File(paths[1]).readAsStringSync();
    final certificates =
        File(paths[2]).readAsStringSync();

    expect(statements, contains("SkoLanguageController.tr('給与明細')"));
    expect(review, contains("SkoLanguageController.tr('給料一覧')"));
    expect(certificates, contains("SkoLanguageController.tr('支払証明書')"));
  });

  test('English pack contains finance status labels', () {
    final english = File(
      'lib/international/languages/en/english_language_pack.dart',
    ).readAsStringSync();
    for (final key in ['給料一覧', '確認済み', '未確定', '支払証明書', '下書き', '確定']) {
      expect(english, contains("'$key':"));
    }
  });
}
