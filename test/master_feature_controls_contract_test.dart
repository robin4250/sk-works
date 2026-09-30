import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('master feature controls are reversible and master-only for writes', () {
    final sql = File(
      'supabase/migrations/20260930065000_add_master_feature_controls.sql',
    ).readAsStringSync();

    expect(sql, contains("'vehicle_management'"));
    expect(sql, contains("'route_assignment'"));
    expect(sql, contains('enabled boolean not null default true'));
    expect(sql, contains('public.is_current_user_master_admin()'));
    expect(sql, contains('set_master_feature_enabled'));
    expect(sql, contains('current_master_feature_flags'));
    expect(sql, contains('on conflict (feature_key) do update'));
    expect(sql, isNot(contains('delete from')));
  });

  test('ordinary authenticated users can only read availability flags', () {
    final sql = File(
      'supabase/migrations/20260930065000_add_master_feature_controls.sql',
    ).readAsStringSync();

    expect(
      sql,
      contains('grant execute on function public.current_master_feature_flags() to authenticated'),
    );
    expect(
      sql,
      contains('grant execute on function public.set_master_feature_enabled(text,boolean)'),
    );
    expect(sql, contains('master administrator access required'));
    expect(sql, contains('revoke all on private.master_feature_settings'));
  });
}
