import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('payroll is rebuilt as the adopted card-style A4 document', () {
    final s=File('lib/features/payroll/payroll_pdf_service.dart').readAsStringSync();
    expect(s, contains("'勤務実績'"));
    expect(s, contains("'支給（＋）'"));
    expect(s, contains("'控除（－）'"));
    expect(s, contains('_attendanceCards'));
    expect(s, contains('_moneyPanel'));
    expect(s, contains('_summaryAmount'));
    expect(s, contains("'給与形態'"));
    expect(s, contains("'休日深夜残業'"));
    expect(s, contains('pw.Spacer()'));
    expect(s, isNot(contains("_balancedMoneySection(\n          title: '支給'")));
  });
}
