import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('payment certificate PDF follows supplied construction payment form', () {
    final source = File(
      'lib/features/payroll/payment_certificate_pdf_service.dart',
    ).readAsStringSync();

    expect(source, contains("'工事代金支払明細書'"));
    expect(source, contains("'下記の通りお支払いたします。'"));
    expect(source, contains("'作業所名 / 工事内容'"));
    expect(source, contains("'数量'"));
    expect(source, contains("'単価'"));
    expect(source, contains("'支払金額'"));
    expect(source, contains("'合計'"));
    expect(source, contains("'法定福利費'"));
    expect(source, contains("'消費税'"));
    expect(source, contains("'差引残高'"));
    expect(source, contains('pw.Table('));
  });
}
