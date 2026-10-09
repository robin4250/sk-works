import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/payroll_statement_repository.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('employee payroll statement loads revision review status', () {
    final repository = read(
      'lib/features/payroll/payroll_statement_repository.dart',
    );
    expect(repository, contains('my_payroll_review_statuses'));
    final row = <String, dynamic>{
      'id': 'statement',
      'workflow_state': 'draft',
      'review_confirmed': false,
      'period_start': '2026-09-01',
      'period_end': '2026-09-30',
      'detail': <String, dynamic>{},
    };
    expect(payrollStatementFromRow(row, {'review_confirmed': true})
        .reviewConfirmed, isTrue);
    expect(payrollStatementFromRow(row, {'review_confirmed': false})
        .reviewConfirmed, isFalse);

    // A current month status cannot relabel saved finalized or unknown rows.
    for (final state in ['finalized', null]) {
      final saved = {...row, 'workflow_state': state, 'review_confirmed': true};
      expect(payrollStatementFromRow(saved, {'review_confirmed': false})
          .reviewConfirmed, isTrue);
      final unconfirmed = {...saved, 'review_confirmed': false};
      expect(payrollStatementFromRow(unconfirmed, {'review_confirmed': true})
          .reviewConfirmed, isFalse);
    }
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
      contains("SkoLanguageController.isEnglish ? 'Unconfirmed' : '未確認'"),
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
    expect(pdf, contains("statement.reviewConfirmed ? '確認済み' : '未確認'"));
  });
}
