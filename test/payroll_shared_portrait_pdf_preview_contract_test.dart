import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
void main() {
  test('payroll preview uses the same portrait A4 PDF builder', () {
    final s=File('lib/features/payroll/payroll_statements_page.dart').readAsStringSync();
    expect(s, contains('initialPageFormat: PdfPageFormat.a4,'));
    expect(s, isNot(contains('PdfPageFormat.a4.landscape')));
    expect(s, contains('build: (_) => PayrollPdfService.buildPdf(statement)'));
    expect(s, contains('allowPrinting: true'));
    expect(s, contains('allowSharing: true'));
  });
}
