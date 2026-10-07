import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('invoice keeps the approved reference structure', () {
    final s=File('lib/features/invoices/invoice_pdf_service.dart').readAsStringSync();
    expect(s, contains("'御　請　求　書'"));
    expect(s, contains('while (rows.length < 35)'));
    expect(s, contains("'御請求金額'"));
    expect(s, contains("'振込先："));
    expect(s, contains("'件名 ／ 工期'"));
    expect(s, contains("'作業所名'"));
    expect(s, contains("'工事内容'"));
    expect(s, contains("'数量'"));
    expect(s, contains("'単価'"));
    expect(s, contains("'請求金額'"));
    expect(s, contains("'合計(税込)'"));
    expect(s, contains('approvals.take(3)'));
    expect(s, isNot(contains('_surnameForStamp')));
  });
}
