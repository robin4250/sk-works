import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('daily report approval duty is explicitly assigned', () {
    final migration = File(
      'supabase/migrations/20260921220500_configurable_daily_report_approvers.sql',
    ).readAsStringSync();
    final page =
        File('lib/features/people/member_permission_page.dart').readAsStringSync();

    expect(migration, contains('company_approval_assignees'));
    expect(migration, contains('approval assignee must be sub-admin or above'));
    expect(migration, contains('approval_assignee_limit_reached'));
    expect(migration, contains('at_least_one_approval_assignee_required'));
    expect(migration, contains('approvals_required set default 1'));
    expect(page, contains('承認担当者（1〜3名）'));
    expect(page, contains('承認担当者は最大3名です'));
    expect(page, contains('現在登録中の3名のうち誰か1名を外してください'));
    expect(page, contains('この人を外す'));
  });
}
