import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/shared/company_seal_pdf.dart';

void main() {
  test('seal uses registered company name and never a fixed bitmap', () {
    expect(CompanySealPdf.verticalColumns(''), isEmpty);
    expect(CompanySealPdf.verticalColumns('株式会社テスト'), isNotEmpty);
    expect(CompanySealPdf.verticalColumns('株式会社テスト'), isNot(
      CompanySealPdf.verticalColumns('別会社'),
    ));
  });

  test('all three document generators use shared company seal', () {
    final sources = [
      'lib/features/invoices/invoice_pdf_service.dart',
      'lib/features/payroll/payroll_pdf_service.dart',
      'lib/features/payroll/payment_certificate_pdf_service.dart',
    ];
    for (final path in sources) {
      expect(File(path).readAsStringSync(), contains('CompanySealPdf.build('));
    }
    expect(
      File(sources.last).readAsStringSync(),
      isNot(contains("'会社印'")),
    );
  });
}
