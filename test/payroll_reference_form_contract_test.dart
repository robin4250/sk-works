import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('payroll PDF follows supplied statement-style table layout', () {
    final source =
        File('lib/features/payroll/payroll_pdf_service.dart').readAsStringSync();

    expect(source, contains("'給与明細書'"));
    expect(source, contains("'勤怠'"));
    expect(source, contains("'支給'"));
    expect(source, contains("'控除'"));
    expect(source, contains("'総支給額'"));
    expect(source, contains("'総控除額'"));
    expect(source, contains("'差引支給額'"));
    expect(source, contains("'月次減税額'"));
    expect(source, contains('pw.Table('));
    expect(source, contains('PdfPageFormat.a4.landscape'));
    expect(source, contains("PdfColor.fromHex('#DCE8F6')"));
    expect(source, contains("statement.reviewConfirmed ? '確認済み' : '未確定'"));
  });
}
