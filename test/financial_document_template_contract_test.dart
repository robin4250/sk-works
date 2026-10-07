import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('invoice PDF follows provided construction invoice template', () {
    final source = read('lib/features/invoices/invoice_pdf_service.dart');
    expect(source, contains("'御　請　求　書'"));
    expect(source, contains("'請求書番号：\${invoice.invoiceNumber}'"));
    expect(source, contains("'御請求金額'"));
    expect(source, contains("'振込先："));
    expect(source, contains("'件名 ／ 工期'"));
    expect(source, contains("'作業所名'"));
    expect(source, contains("'工事内容'"));
    expect(source, contains("'数量'"));
    expect(source, contains("'単価'"));
    expect(source, contains("'請求金額'"));
    expect(source, contains("'合計(税込)'"));
  });

  test('payroll PDF uses adopted A4 payroll statement template', () {
    final source = read('lib/features/payroll/payroll_pdf_service.dart');
    expect(source, contains('PdfPageFormat.a4,'));
    expect(source, contains("'給与明細書'"));
    expect(source, contains("'勤務実績'"));
    expect(source, contains("'2　　支給（＋）'"));
    expect(source, contains("'3　　控除（－）'"));
    expect(source, contains("'支給合計（A）'"));
    expect(source, contains("'控除合計（B）'"));
    expect(source, contains("'差引支給額'"));
  });

  test(
    'payment certificate follows provided construction payment template',
    () {
      final source = read(
        'lib/features/payroll/payment_certificate_pdf_service.dart',
      );
      expect(source, contains("'工事代金支払明細書'"));
      expect(source, contains("'作　業　所　名'"));
      expect(source, contains("'工　事　内　容'"));
      expect(source, contains("'数　量'"));
      expect(source, contains("'単　価'"));
      expect(source, contains("'支払金額'"));
      expect(source, contains("'差　引　残　高'"));
    },
  );
}
