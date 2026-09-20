import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manager default approval behavior stays consistent', () {
    final migration = File(
      'supabase/migrations/20260920220000_restore_manager_default_approval_notifications.sql',
    ).readAsStringSync();
    final baseline = File(
      'supabase/migrations/20260920004000_add_member_feature_permissions.sql',
    ).readAsStringSync();

    expect(
      migration,
      contains('coalesce(mfp.can_approve_daily_report_edits, true)'),
    );
    expect(
      baseline,
      contains("'can_approve_daily_report_edits', v_role = 'manager'"),
    );
    expect(
      baseline,
      contains("'can_manage_attendance', v_role = 'manager'"),
    );
  });
}
