import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('payroll reference form keeps readable row spacing and labels', () {
    final source =
        File('lib/features/payroll/payroll_pdf_service.dart').readAsStringSync();

    expect(source, contains("height: 18"));
    expect(source, contains("'出勤日数'"));
    expect(source, contains("'休出日数'"));
    expect(source, contains("'残業時間'"));
    expect(source, contains("'法定休出時間'"));
    expect(source, contains("'基本給'"));
    expect(source, contains("'残業手当'"));
    expect(source, contains("'勤続手当'"));
    expect(source, contains("'役職手当'"));
    expect(source, contains("'家族手当'"));
    expect(source, contains("'働き方手当'"));
    expect(source, contains("'健康保険料'"));
    expect(source, contains("'介護保険料'"));
    expect(source, contains("'厚生年金保険'"));
    expect(source, contains("'雇用保険料'"));
    expect(source, contains("'所得税'"));
    expect(source, contains("'住民税'"));
    expect(source, contains("'SKB会費'"));
    expect(source, contains("'道具代'"));
    expect(source, contains("'総支給額'"));
    expect(source, contains("'総控除額'"));
    expect(source, contains("'差引支給額'"));
    expect(source, contains("'日給単価'"));
    expect(source, contains("'月次減税額'"));
  });
}
