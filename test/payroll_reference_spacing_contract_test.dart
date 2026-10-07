import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('payroll reference uses re-read labels from supplied image', () {
    final pdf = read('lib/features/payroll/payroll_pdf_service.dart');

    expect(pdf, contains("'出勤日数'"));
    expect(pdf, contains("'休出日数'"));
    expect(pdf, contains("'残業時間'"));
    expect(pdf, contains("'法定休出時間'"));
    expect(pdf, contains("'基本給'"));
    expect(pdf, contains("'残業手当'"));
    expect(pdf, contains("'健康保険料'"));
    expect(pdf, contains("'所得税'"));
    expect(pdf, contains("'住民税'"));
    expect(pdf, contains("'custom_earnings'"));
    expect(pdf, contains("'custom_deductions'"));
    expect(pdf, contains('_balancedMoneySection'));
  });

  test('payroll rows reserve readable vertical space', () {
    final pdf = read('lib/features/payroll/payroll_pdf_service.dart');

    expect(pdf, contains('height: 18'));
    expect(pdf, contains('height: 25'));
    expect(pdf, contains('height: 22'));
    expect(pdf, contains('maxLines: 1'));
    expect(pdf, contains('height: 23'));
    expect(pdf, contains('pw.Alignment.center'));
  });

  test('payroll keeps reference totals and tax footer grid', () {
    final pdf = read('lib/features/payroll/payroll_pdf_service.dart');

    expect(pdf, contains("'総支給額'"));
    expect(pdf, contains("'総控除額'"));
    expect(pdf, contains("'差引支給額'"));
    expect(pdf, contains("'日給単価'"));
    expect(pdf, contains("'月次減税額'"));
    expect(pdf, contains("'減税前未済額'"));
    expect(pdf, contains("'減税前所得税'"));
    expect(pdf, contains("'定額減税額'"));
    expect(pdf, contains("'定額減税未済'"));
    expect(pdf, contains("'お疲れさまです。'"));
  });
}
