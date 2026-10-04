import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('payroll sub-admin visibility checklist is hide-based', () {
    final source =
        File('lib/features/payroll/payroll_review_page.dart').readAsStringSync();

    expect(source, contains('サブ管理者に見せない従業員'));
    expect(source, contains('非表示にする従業員だけチェックしてください'));
    expect(source, contains('value: !worker.visibleToManager'));
    expect(source, contains('visible: !hidden'));
    expect(source, isNot(contains('サブ管理者へ見せる従業員')));
  });
}
