import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('company rate settings stay behind admin RPCs', () {
    final sql = File(
      'supabase/migrations/20260922020000_add_company_rate_settings_management.sql',
    ).readAsStringSync();

    expect(sql, contains('company_rate_settings_state'));
    expect(sql, contains('save_company_rate_settings'));
    expect(sql, contains("role::text in ('owner','admin')"));
    expect(sql, contains('revoke execute'));
    expect(sql, contains('grant execute'));
  });

  test('settings page exposes editable company rates for admins', () {
    final settings =
        File('lib/features/settings/settings_page.dart').readAsStringSync();
    final page = File(
      'lib/features/settings/company_rate_settings_page.dart',
    ).readAsStringSync();

    expect(settings, contains('会社単価・手当設定'));
    expect(settings, contains('if (_canManageCompany)'));
    expect(page, contains('福利厚生費率'));
    expect(page, contains('残業単価'));
    expect(page, contains('早出単価'));
    expect(page, contains('夜勤単価'));
    expect(page, contains('休日出勤単価'));
    expect(page, contains('手当1 名称'));
    expect(page, contains('手当2 名称'));
    expect(page, contains('手当3 名称'));
  });
}
