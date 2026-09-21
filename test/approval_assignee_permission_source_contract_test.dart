import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('current approval permission follows configured assignee table', () {
    final sql = File(
      'supabase/migrations/20260922021500_align_approval_assignee_permission_source.sql',
    ).readAsStringSync();

    expect(sql, contains('company_approval_assignees'));
    expect(sql, contains('v_is_approval_assignee'));
    expect(
      sql,
      contains("'can_approve_daily_report_edits', v_is_approval_assignee"),
    );
    expect(
      sql,
      isNot(
        contains("'can_approve_daily_report_edits', v_role = 'manager'"),
      ),
    );
  });

  test('approval UI remains driven by current feature permission', () {
    final source = File('lib/app_v2.dart').readAsStringSync();

    expect(
      source,
      contains("_identity.can('can_approve_daily_report_edits')"),
    );
  });
}
