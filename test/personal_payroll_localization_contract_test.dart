import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('personal payslip pages support English display', () {
    final source =
        File('lib/features/payroll/payroll_statements_page.dart').readAsStringSync();

    expect(source, contains("SkoLanguageController.isEnglish ? 'Payslips'"));
    expect(source, contains("'No payslips have been issued yet.'"));
    expect(source, contains("'PAYSLIP'"));
    expect(source, contains("'Gross Pay'"));
    expect(source, contains("'Deductions'"));
    expect(source, contains("'Net Pay'"));
    expect(source, contains("'Confirmed'"));
    expect(source, contains("'Unconfirmed'"));
    expect(source, contains("'Print'"));

    // Keep the personal-only repository boundary.
    expect(source, contains('loadMyStatements()'));
  });
}
