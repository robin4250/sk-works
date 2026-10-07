import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('final payroll A4 design contract', () {
    final source = File('lib/features/payroll/payroll_pdf_service.dart')
        .readAsStringSync();
    expect(source, contains('pageFormat: PdfPageFormat.a4,'));
    expect(source, contains("'休日深夜残業'"));
    expect(source, contains('_isZeroDisplay'));
    expect(source, contains("PdfColor.fromHex('#BCCADD')"));
    expect(source, contains("PdfColor.fromHex('#073A76')"));
    expect(source, contains('_isAggregatePlaceholder'));
    expect(source, contains('label.isEmpty || amount == null'));
  });

  test('final invoice A4 design contract', () {
    final source = File('lib/features/invoices/invoice_pdf_service.dart')
        .readAsStringSync();
    expect(source, contains('while (rows.length < 35)'));
    expect(source, contains('for (var i = 0; i < 3; i++)'));
    expect(source, contains('approvals[i].approved'));
    expect(source, contains("PdfColor.fromHex('#B7BEC6')"));
    expect(source, isNot(contains('_surnameForStamp')));
    expect(source, contains("'　お振込先'"));
  });
}
