import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sub-admin financial permissions are forced off in DB', () {
    final sql = File(
      'supabase/migrations/20260922022500_enforce_subadmin_financial_boundary.sql',
    ).readAsStringSync();

    for (final marker in [
      'can_view_invoices = false',
      'can_manage_invoices = false',
      'can_view_admin_site_data = false',
      'can_manage_admin_site_data = false',
      'can_manage_payroll = false',
    ]) {
      expect(sql, contains(marker));
    }
  });

  test('sub-admin permission UI hides financial controls', () {
    final page =
        File('lib/features/people/member_permission_page.dart').readAsStringSync();

    expect(page, contains('サブ管理者は請求書・管理者用現場データ（現場単価）・給与管理を利用できません'));
    expect(page, contains('本人の給与明細は一般ユーザーと同じように第2認証で確認できます'));

    expect(page, isNot(contains("'can_view_invoices': '請求書を見る'")));
    expect(page, isNot(contains("'can_manage_invoices': '請求書設定・管理'")));
    expect(page, isNot(contains("'can_view_admin_site_data': '管理者用現場データを見る'")));
    expect(page, isNot(contains("'can_manage_admin_site_data': '管理者用現場データを編集'")));
    expect(page, isNot(contains("'can_manage_payroll': '給与管理'")));
  });
}
