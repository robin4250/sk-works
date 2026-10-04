import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('invoice PDF follows provided construction invoice template', () {
    final source = read('lib/features/invoices/invoice_pdf_service.dart');
    expect(source, contains("'御 請 求 書'"));
    expect(source, contains("'請求書番号:'"));
    expect(source, contains("'御請求金額'"));
    expect(source, contains("'振込先'"));
    expect(source, contains("'件名 / 工期  \${invoice.billingPeriod}'"));
    expect(source, contains("['整理番号', '内容', '人工', '残業', '金額']"));
    expect(source, contains("'合計(税込)'"));
  });

  test('payroll PDF uses provided landscape payroll statement template', () {
    final source = read('lib/features/payroll/payroll_pdf_service.dart');
    expect(source, contains('PdfPageFormat.a4.landscape'));
    expect(source, contains("'給与明細書'"));
    expect(source, contains("'勤怠・支給・控除'"));
    expect(source, contains("'総支給額'"));
    expect(source, contains("'総控除額'"));
    expect(source, contains("'差引支給額'"));
  });

  test('payment certificate follows provided construction payment template', () {
    final source = read(
      'lib/features/payroll/payment_certificate_pdf_service.dart',
    );
    expect(source, contains("'工事代金支払明細書'"));
    expect(source, contains("'作業所名 / 工事内容'"));
    expect(source, contains("'数量'"));
    expect(source, contains("'単価'"));
    expect(source, contains("'支払金額'"));
    expect(source, contains("'法定福利費'"));
    expect(source, contains("'消費税'"));
    expect(source, contains("'差引残高'"));
  });
}
