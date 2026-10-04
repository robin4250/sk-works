import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('invoice PDF follows supplied Japanese construction invoice form', () {
    final source =
        File('lib/features/invoices/invoice_pdf_service.dart').readAsStringSync();

    expect(source, contains("'御請求書'"));
    expect(source, contains("'御請求金額'"));
    expect(source, contains("'工事内容 / 現場'"));
    expect(source, contains("'数量'"));
    expect(source, contains("'単価'"));
    expect(source, contains("'合計(税込)'"));
    expect(source, contains('PdfColors.blueGrey100'));
  });
}
