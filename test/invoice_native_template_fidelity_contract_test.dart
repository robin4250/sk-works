import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native invoice preview keeps formal A4 invoice structure', () {
    final source =
        File('lib/features/invoices/invoice_pdf_service.dart').readAsStringSync();

    expect(source, contains('height: 842'));
    expect(source, contains('settings?.templateTitle'));
    expect(source, contains('settings?.companyName'));
    expect(source, contains('settings?.companyAddress'));
    expect(source, contains('settings?.companyPhone'));
    expect(source, contains("'ご請求金額"));
    expect(source, contains("'振込先"));
    expect(source, contains('settings?.bankAccountNumber'));
    expect(source, contains('settings?.footerNote'));
    expect(source, contains('approvals.take(3)'));
    expect(source, contains('_sealBytes(settings?.companySealBase64)'));
  });

  test('screen title does not leak preview label into the invoice document', () {
    final source =
        File('lib/features/invoices/invoice_pdf_service.dart').readAsStringSync();

    expect(source, contains("settings!.templateTitle.trim()"));
    expect(source, contains(": '請求書'"));
    expect(
      source,
      isNot(contains("title ?? '請求書'")),
    );
  });

  test('print and share still use generated PDF bytes', () {
    final source =
        File('lib/features/invoices/invoice_pdf_service.dart').readAsStringSync();

    expect(source, contains('onLayout: (_) async => pdfBytes'));
    expect(source, contains('bytes: pdfBytes'));
    expect(source, contains('InvoicePdfService.buildPdf('));
  });
}
