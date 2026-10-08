import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('employee payroll statement loads revision review status', () {
    final repository = read(
      'lib/features/payroll/payroll_statement_repository.dart',
    );
    expect(repository, contains('my_payroll_review_statuses'));
    expect(repository, contains('reviewConfirmed'));
    expect(repository, contains("review?['review_confirmed'] == true"));
  });

  test('employee payroll statement shows confirmed or unconfirmed label', () {
    final page = read('lib/features/payroll/payroll_statements_page.dart');
    final normalized = page.replaceAll(RegExp(r'\s+'), ' ');
    expect(
      normalized,
      contains("SkoLanguageController.isEnglish ? 'Confirmed' : '確認済み'"),
    );
    expect(
      normalized,
      contains("SkoLanguageController.isEnglish ? 'Unconfirmed' : '未確定'"),
    );
    expect(
      normalized,
      contains(
        "item.reviewConfirmed ? (SkoLanguageController.isEnglish ? 'Confirmed' : '確認済み')",
      ),
    );
    expect(page, contains('Colors.green'));
  });

  test('printed payroll statement keeps review status in the margin', () {
    final pdf = read('lib/features/payroll/payroll_pdf_service.dart');
    expect(pdf, contains("statement.reviewConfirmed ? '確認済み' : '未確定'"));
  });
}
