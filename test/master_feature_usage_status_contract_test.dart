import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Master feature usage status distinguishes disabled and unused', () {
    final sql = File(
      'supabase/migrations/20260930130000_add_master_feature_usage_status.sql',
    ).readAsStringSync();

    expect(sql, contains("'disabled'"));
    expect(sql, contains("'enabled_unused'"));
    expect(sql, contains("'enabled_used'"));
    expect(sql, contains("'disabled_features'"));
    expect(sql, contains("'enabled_unused_features'"));
    expect(sql, contains("'enabled_used_features'"));
    expect(sql, contains("'event_count'"));
    expect(sql, contains("'company_count'"));
    expect(sql, contains("'user_count'"));
    expect(sql, contains('private.master_feature_settings'));
    expect(sql, contains('private.master_usage_events'));
    expect(sql, contains('public.is_current_user_master_admin()'));
    expect(sql, contains('from public, anon'));

    for (final forbidden in <String>[
      "'company_id'",
      "'user_id'",
      "'phone'",
      "'email'",
      "'metadata'",
    ]) {
      expect(sql, isNot(contains(forbidden)));
    }
  });
}
