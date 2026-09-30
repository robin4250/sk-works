import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('usage event RPC accepts only fixed product keys and no free-form metadata', () {
    final sql = File(
      'supabase/migrations/20260930102000_add_master_usage_event_rpc.sql',
    ).readAsStringSync();

    expect(sql, contains("p_event_key not in ('page_view','action')"));
    expect(sql, contains("'home'"));
    expect(sql, contains("'attendance'"));
    expect(sql, contains("'company_exchange'"));
    expect(sql, contains("'vehicle_routes'"));
    expect(sql, contains("'clock_in'"));
    expect(sql, contains("'clock_out'"));
    expect(sql, contains("'print'"));
    expect(sql, contains("'send'"));
    expect(sql, contains("'{}'::jsonb"));
    expect(sql, contains('No free-form metadata'));
  });

  test('usage ranking is Master-only aggregate data', () {
    final sql = File(
      'supabase/migrations/20260930102000_add_master_usage_event_rpc.sql',
    ).readAsStringSync();

    expect(sql, contains('public.is_current_user_master_admin()'));
    expect(sql, contains('events_total'));
    expect(sql, contains('companies_active'));
    expect(sql, contains('users_active'));
    expect(sql, contains('event_count'));
    expect(sql, contains('company_count'));
    expect(sql, contains('user_count'));
    expect(sql, contains('limit 50'));
    expect(sql, contains('p_days not in (7,30,90)'));
    expect(sql, contains('from public, anon'));
    expect(sql, isNot(contains('message_body')));
    expect(sql, isNot(contains('latitude')));
    expect(sql, isNot(contains('longitude')));
  });
}
