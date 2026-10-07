import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('invoice PDF follows supplied Japanese construction invoice form', () {
    final source = File('lib/features/invoices/invoice_pdf_service.dart')
        .readAsStringSync();

    expect(source, contains("'請　求　書'"));
    expect(source, contains("'ご請求金額（税込）'"));
    expect(source, contains("'現場名'"));
    expect(source, contains("'工事内容・摘要'"));
    expect(source, contains("'人数'"));
    expect(source, contains("'単価（円）'"));
    expect(source, contains("'金額（円）'"));
    expect(source, contains("'小計（税抜）'"));
    expect(source, contains("PdfColor.fromHex('#138BE1')"));
  });
}
