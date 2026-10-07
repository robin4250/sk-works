import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
String read(String p)=>File(p).readAsStringSync();
void main(){
 test('invoice uses attendance facts and billing settings, not site worker payroll rates',(){
  final sql=read('supabase/migrations/20261006173142_common_rate_formula_invoice_hourly.sql');
  expect(sql,contains('from public.attendance_entries e'));
  expect(sql,contains('fs.billing_unit_price_yen'));
  expect(sql,contains('s.billing_rate_formula'));
  expect(sql,isNot(contains('s.worker_rate_formula')));
 });
 test('individual payroll owns employee pay settings',(){
  final repo=read('lib/features/payroll/individual_payroll_settings_repository.dart');
  expect(repo,contains("from('worker_payroll_settings')"));
  final page=read('lib/features/payroll/individual_payroll_settings_page.dart');
  expect(page,contains("['day_daily']"));
 });
 test('partner payment is intentionally separate from employee payroll and customer billing',(){
  final migration=read('supabase/migrations/20261006174658_fix_payment_certificate_detail_formula_fallbacks.sql');
  expect(migration,contains('partner_payment_settings'));
  expect(migration,contains('attendance_entries'));
 });
}
