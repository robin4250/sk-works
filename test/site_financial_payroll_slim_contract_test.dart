import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
void main(){
 test('site financial UI exposes billing settings only and preserves legacy payroll values',(){
  final s=File('lib/features/sites/admin_site_financial_page.dart').readAsStringSync();
  expect(s,isNot(contains("'給与計算用'")));
  expect(s,isNot(contains("'給与 ${_yen(item.workerDailyRateYen)}")));
  expect(s,contains("'請求書用'"));
  expect(s,contains('workerDailyRateYen: record.workerDailyRateYen'));
  expect(s,contains('workerFormulas: record.workerFormulas'));
  expect(s,contains('workerRateOverrides: record.workerRateOverrides'));
 });
}
