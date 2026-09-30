import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('usage ingestion records only bounded product keys', () {
    final sql = File(
      'supabase/migrations/20260930102000_add_master_usage_event_ingestion.sql',
    ).readAsStringSync();

    expect(sql, contains('public.record_usage_event'));
    expect(sql, contains('v_user_id uuid := auth.uid()'));
    expect(sql, contains('select cm.company_id'));
    expect(sql, contains('private.master_usage_events'));
    expect(sql, contains('invalid event key'));
    expect(sql, contains(r'^[a-z0-9][a-z0-9_.:-]*$'));
    expect(sql, isNot(contains('p_metadata')));
    expect(sql, isNot(contains('p_company_id')));
    expect(sql, isNot(contains('p_user_id')));
    expect(sql, contains('from public, anon'));
    expect(sql, contains('master_usage_events_user_recent_idx'));
    expect(sql, contains("interval '1 minute'"));
    expect(sql, contains('>= 120'));
    expect(sql, contains('usage event rate limit exceeded'));
  });

  test('Master usage snapshot returns aggregate rankings only', () {
    final sql = File(
      'supabase/migrations/20260930102000_add_master_usage_event_ingestion.sql',
    ).readAsStringSync();

    expect(sql, contains('public.get_master_usage_snapshot'));
    expect(sql, contains('public.is_current_user_master_admin()'));
    expect(sql, contains("'events_total'"));
    expect(sql, contains("'companies_active'"));
    expect(sql, contains("'users_active'"));
    expect(sql, contains("'top_events'"));
    expect(sql, contains("'top_surfaces'"));
    expect(sql, contains("'top_features'"));
    expect(sql, contains('least(coalesce(p_days,30),365)'));

    for (final forbidden in <String>[
      'chat_messages',
      'storage.objects',
      'workers.phone',
      'document_submissions',
      'latitude',
      'longitude',
    ]) {
      expect(sql, isNot(contains(forbidden)));
    }
  });
}
