import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('employee payroll statement loads revision review status', () {
    final repository =
        read('lib/features/payroll/payroll_statement_repository.dart');
    expect(repository, contains('my_payroll_review_statuses'));
    expect(repository, contains('reviewConfirmed'));
    expect(repository, contains("review?['review_confirmed'] == true"));
  });

  test('employee payroll statement shows confirmed or unconfirmed label', () {
    final page = read('lib/features/payroll/payroll_statements_page.dart');
    expect(page, contains("item.reviewConfirmed ? '確認済み' : '未確定'"));
    expect(page, contains("statement.reviewConfirmed ? '確認済み' : '未確定'"));
    expect(page, contains('Colors.green'));
    expect(page, contains('colorScheme.error'));
  });

  test('printed payroll statement keeps review status in the margin', () {
    final pdf = read('lib/features/payroll/payroll_pdf_service.dart');
    expect(pdf, contains("statement.reviewConfirmed ? '確認済み' : '未確定'"));
    expect(pdf, contains('PdfColors.green700'));
    expect(pdf, contains('PdfColors.red700'));
  });
}
