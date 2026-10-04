import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('invoice PDF follows supplied Japanese construction invoice form', () {
    final source =
        File('lib/features/invoices/invoice_pdf_service.dart').readAsStringSync();

    expect(source, contains("'御　請　求　書'"));
    expect(source, contains("'御請求金額'"));
    expect(source, contains("'内容'"));
    expect(source, contains("'人工'"));
    expect(source, contains("'残業'"));
    expect(source, contains("'整理番号'"));
    expect(source, contains("'合計(税込)'"));
    expect(source, contains("PdfColor.fromHex('#8199B5')"));
  });
}
