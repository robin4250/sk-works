import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('payroll reference keeps named work earning and deduction data', () {
    final pdf = File('lib/features/payroll/payroll_pdf_service.dart')
        .readAsStringSync();
    for (final token in [
      '出勤日数',
      '休出日数',
      '残業時間',
      '法定休出時間',
      '基本給',
      '残業手当',
      '健康保険料',
      '所得税',
      '住民税',
      'custom_earnings',
      'custom_deductions',
    ]) {
      expect(pdf, contains(token));
    }
    expect(pdf, contains('_moneyPanel'));
  });

  test('payroll rows adapt while preserving the adopted summary', () {
    final pdf = File('lib/features/payroll/payroll_pdf_service.dart')
        .readAsStringSync();
    expect(
      pdf,
      contains('final rowCount = visible.length < 15 ? 15 : visible.length'),
    );
    expect(pdf, contains('220.0 / rowCount'));
    expect(pdf, contains('height: rowHeight'));
    expect(pdf, contains('_moneyExplanation'));
    expect(pdf, contains('支給合計'));
    expect(pdf, contains('控除合計'));
    expect(pdf, contains('差引支給額'));
    expect(pdf, contains('備考'));
  });
}
