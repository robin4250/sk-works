import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production payroll locks the approved v4 soft A4 contract', () {
    final s = File('lib/features/payroll/payroll_pdf_service.dart')
        .readAsStringSync();
    expect(s, contains("PdfColor.fromHex('#178DE3')"));
    expect(s, contains("PdfColor.fromHex('#EC4F79')"));
    expect(s, contains("PdfColor.fromHex('#318B61')"));
    expect(s, contains('final panelWidth = (width - 10) / 2'));
    expect(s, contains('offset: const PdfPoint(-4, 0)'));
    expect(
      s,
      contains("final rowCount = visible.length < 15 ? 15 : visible.length"),
    );
    expect(s, contains("220.0 / rowCount"));
    expect(s, contains("'2　●　支給（＋）'"));
    expect(s, contains("'3　　控除（－）'"));
    expect(s, contains("'差引支給額'"));
  });
}
