import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('admin setup keeps employee invite onboarding states intact', () {
    final gate = read('lib/features/auth/auth_gate.dart');
    final pages = read('lib/features/auth/secure_onboarding_pages.dart');

    expect(gate, contains('_GateStatus.employeePassword'));
    expect(gate, contains('_GateStatus.employeeProfile'));
    expect(gate, contains('_GateStatus.employeeApprovalPending'));
    expect(gate, contains('_GateStatus.needsAdminInitialSetup'));
    expect(pages, contains('従業員登録QRコードからログイン'));
  });

  test('new companies require guided initial setup without affecting existing companies', () {
    final sql = read(
      'supabase/migrations/20260922013000_add_admin_initial_setup_wizard.sql',
    );

    expect(sql, contains('company_initial_setup_progress'));
    expect(sql, contains('Existing production companies must not be pushed back'));
    expect(sql, contains('insert into public.company_initial_setup_progress(company_id)'));
    expect(sql, contains('company_profile_completed'));
    expect(sql, contains('document_requirements_reviewed'));
    expect(sql, contains('first_site_completed'));
    expect(sql, contains('rate_settings_completed'));
  });

  test('initial company profile creates the owner worker record', () {
    final sql = read(
      'supabase/migrations/20260922013000_add_admin_initial_setup_wizard.sql',
    );

    expect(sql, contains('insert into public.workers'));
    expect(sql, contains("'employee'"));
    expect(sql, contains("'管理者'"));
    expect(sql, contains('user_id'));
  });

  test('initial site captures billing customer address station and site rate', () {
    final sql = read(
      'supabase/migrations/20260922013000_add_admin_initial_setup_wizard.sql',
    );
    final page = read('lib/features/auth/admin_initial_setup_page.dart');

    expect(sql, contains('nearest_station'));
    expect(sql, contains('p_customer_name'));
    expect(sql, contains('p_site_address'));
    expect(sql, contains('p_billing_unit_price_yen'));

    expect(page, contains('請求先会社名'));
    expect(page, contains('現場住所'));
    expect(page, contains('最寄り駅'));
    expect(page, contains('現場単価'));
  });

  test('initial rate setup includes requested pay rates and three allowances', () {
    final sql = read(
      'supabase/migrations/20260922013000_add_admin_initial_setup_wizard.sql',
    );
    final page = read('lib/features/auth/admin_initial_setup_page.dart');

    for (final item in [
      'p_tax_rate',
      'p_welfare_rate',
      'p_overtime_hour_rate_yen',
      'p_early_hour_rate_yen',
      'p_night_hour_rate_yen',
      'p_holiday_day_rate_yen',
      'p_allowance_1_name',
      'p_allowance_2_name',
      'p_allowance_3_name',
    ]) {
      expect(sql, contains(item));
    }

    for (final label in [
      '消費税率',
      '福利厚生費率',
      '残業単価',
      '早出単価',
      '夜勤単価',
      '休日出勤単価',
      '手当1 名称',
      '手当2 名称',
      '手当3 名称',
    ]) {
      expect(page, contains(label));
    }
  });

  test('required documents can be selected now while uploads remain later', () {
    final page = read('lib/features/auth/admin_initial_setup_page.dart');

    expect(page, contains('実際の書類写真やPDFは後から登録できます'));
    expect(page, contains('標準の必要書類を追加'));
    expect(page, contains('会社独自の必要書類を追加'));
    expect(page, contains('大事なお知らせ'));
  });
}
