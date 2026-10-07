import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('final payroll A4 design contract', () {
    final source = File('lib/features/payroll/payroll_pdf_service.dart').readAsStringSync();
    expect(source, contains('pageFormat: PdfPageFormat.a4,'));
    expect(source, contains("'休日深夜残業'"));
    expect(source, contains('_isZeroDisplay'));
    expect(source, contains('PdfColors.grey400'));
    expect(source, contains('_isAggregatePlaceholder'));
    expect(source, contains('amount.abs() < 1'));
  });

  test('final invoice A4 design contract', () {
    final source = File('lib/features/invoices/invoice_pdf_service.dart').readAsStringSync();
    expect(source, contains('while (rows.length < 35)'));
    expect(source, contains('approvals.take(3)'));
    expect(source, isNot(contains('_surnameForStamp')));
    expect(source, contains("'振込先："));
  });
}
