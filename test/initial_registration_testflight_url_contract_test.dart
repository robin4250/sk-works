import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
String read(String p)=>File(p).readAsStringSync();
void main(){
 test('initial registration exposes and saves TestFlight URL',(){
  final page=read('lib/features/people/employee_initial_registration_page.dart');
  final repo=read('lib/features/people/employee_invite_repository.dart');
  final edge=read('supabase/functions/create-employee-invite/index.ts');
  expect(page,contains("'TestFlight誘導URL'"));
  expect(page,contains("'URLを保存'"));
  expect(page,contains("'この従業員へSMSを作成'"));
  expect(page,contains("Uri.parse('sms:"));
  expect(repo,contains("'save_initial_registration_distribution_settings'"));
  expect(edge,contains('employee_testflight_url'));
 });
}
