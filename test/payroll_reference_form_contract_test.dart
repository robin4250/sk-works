import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('payroll PDF follows the adopted A4 card design', () {
    final source = File('lib/features/payroll/payroll_pdf_service.dart')
        .readAsStringSync();
    for (final token in [
      '給与明細書',
      '勤務実績',
      '2　　支給（＋）',
      '3　　控除（－）',
      '支給合計',
      '控除合計',
      '差引支給額',
      '給与形態',
      '社員番号',
      '所属',
      '職種',
      '入社日',
      '_attendanceCards',
      '_moneyPanel',
      '_moneyExplanation',
      '_paymentDate(statement, detail)',
      'PdfPageFormat.a4,',
    ]) {
      expect(source, contains(token));
    }
    expect(source, contains('_customMoneyEntries(detail, direction: 1)'));
    expect(source, contains('_customMoneyEntries(detail, direction: -1)'));
  });

  test('payroll adopted design emphasizes net pay and adapts row height', () {
    final pdf = File('lib/features/payroll/payroll_pdf_service.dart')
        .readAsStringSync();
    expect(pdf, contains('fontSize: 12'));
    expect(pdf, contains('_yen(statement.netPay)'));
    expect(
      pdf,
      contains('final rowCount = visible.length < 15 ? 15 : visible.length'),
    );
    expect(pdf, contains('220.0 / rowCount'));
  });
}
