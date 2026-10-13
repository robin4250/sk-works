import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
String read(String p)=>File(p).readAsStringSync();
void main(){
 test('individual payroll supports daily hourly and monthly salary',(){
  final editor=read('lib/widgets/rate_formula_editor_card.dart');
  final page=read('lib/features/payroll/individual_payroll_settings_page.dart');
  expect(editor,contains("value: 'monthly'"));
  expect(editor,contains("'月固定給'"));
  expect(editor,contains("'計算用 1日基本ベース'"));
  expect(page,contains("['monthly_salary_yen']"));
  expect(page,contains("['calculation_daily_base_yen']"));
 });
 test('monthly fixed salary replaces regular day base while special rates remain calculated',(){
  final sql=read('supabase/migrations/20261007021000_worker_monthly_salary_mode.sql');
  expect(sql,contains("pay_type in ('daily','hourly','monthly')"));
  expect(sql,contains("coalesce(ae.work_category,'day')='day'"));
  expect(sql,contains('monthly_salary_yen'));
  expect(sql,contains("'基本給'"));
 });
}
