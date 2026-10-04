import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('payment certificate PDF follows supplied construction payment form', () {
    final source = File(
      'lib/features/payroll/payment_certificate_pdf_service.dart',
    ).readAsStringSync();

    expect(source, contains("'工事代金支払明細書'"));
    expect(source, contains("'下記の通りお支払いいたします。'"));
    expect(source, contains("'作　業　所　名'"));
    expect(source, contains("'工　事　内　容'"));
    expect(source, contains("'数　量'"));
    expect(source, contains("'単　価'"));
    expect(source, contains("'支払金額'"));
    expect(source, contains("'合　　計'"));
    expect(source, contains("'差　引　残　高'"));
    expect(source, contains('pw.Table('));
  });
}
