import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('payment certificate has printable A4 PDF output', () {
    final service =
        read('lib/features/payroll/payment_certificate_pdf_service.dart');
    final page = read('lib/features/payroll/payment_certificates_page.dart');

    expect(service, contains("'支 払 証 明 書'"));
    expect(service, contains('PdfPageFormat.a4'));
    expect(service, contains('Printing.layoutPdf'));
    expect(service, contains("'支払金額'"));
    expect(page, contains('PaymentCertificatePdfService'));
    expect(page, contains("'印刷'"));
  });
}
