import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('invoice preview renders the actual template PDF', () {
    final source = read('lib/features/invoices/invoice_cloud_page.dart');

    expect(source, contains('InvoicePdfPreviewPage('));
    expect(source, isNot(contains("aspectRatio: 1 / 1.414")));
  });

  test('payroll preview renders the actual landscape template PDF', () {
    final source = read('lib/features/payroll/payroll_statements_page.dart');

    expect(source, contains('PdfPreview('));
    expect(source, contains('PdfPageFormat.a4.landscape'));
    expect(source, contains('PayrollPdfService.buildPdf(statement)'));
  });

  test('payment certificate opens an A4 template PDF preview', () {
    final source = read(
      'lib/features/payroll/payment_certificates_page.dart',
    );

    expect(source, contains('PaymentCertificatePreviewPage'));
    expect(source, contains('PdfPreview('));
    expect(source, contains('PdfPageFormat.a4'));
    expect(
      source,
      contains('PaymentCertificatePdfService.buildPdf(record)'),
    );
  });
}
