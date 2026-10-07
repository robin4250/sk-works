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
    expect(source, contains("'有給日数'"));
    expect(source, contains("'早出時間'"));
    expect(source, contains("'夜間時間'"));
    expect(source, contains("'総控除額'"));
    expect(source, contains("'差引支給額'"));
    expect(source, contains("'月次減税額'"));
    expect(source, contains('pw.Table('));
    expect(source, contains('PdfPageFormat.a4.landscape'));
    expect(source, contains("PdfColor.fromHex('#DCE8F6')"));
    expect(source, contains("statement.reviewConfirmed ? '確認済み' : '未確定'"));
    expect(source, contains('_dayCount(detail'));
    expect(source, contains('_hours(detail'));
    expect(source, contains('_plainNumber(detail'));
    expect(source, contains('earningEntries'));
    expect(source, contains('deductionEntries'));
    expect(source, contains('_balancedMoneySection'));
    expect(source, contains('_customMoneyEntries(detail, direction: 1)'));
    expect(source, contains('_customMoneyEntries(detail, direction: -1)'));
    expect(source, contains('_nonMoneyDetailKeys'));
    expect(source, contains('_fixedMoneyKeys'));
    expect(source, contains('amount.abs()'));
    expect(source, contains("absolute: true"));
    expect(source, contains("_paymentDate(statement, detail)"));
  });
  test('勤怠 支給 控除の左見出しは右表と同じ高さまで縦に伸びる', () {
    final pdf = File('lib/features/payroll/payroll_pdf_service.dart').readAsStringSync();
    expect(pdf, contains('required double sectionHeight'));
    expect(pdf, contains('height: sectionHeight'));
    expect(pdf, contains('sectionHeight: 78'));
    expect(pdf, contains('groups.length * (labelHeight + valueHeight)'));
  });

  test('差引支給額は見出しと金額を大きく太く強調する', () {
    final pdf = File('lib/features/payroll/payroll_pdf_service.dart').readAsStringSync();
    expect(pdf, contains("'差引支給額'"));
    expect(pdf, contains('fontSize: 10.5'));
    expect(pdf, contains('_number(statement.netPay)'));
    expect(pdf, contains('fontSize: 13'));
  });

}
