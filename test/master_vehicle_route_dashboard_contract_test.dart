import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Master dashboard exposes aggregate vehicle route and site chat metrics', () {
    final sql = File(
      'supabase/migrations/20260930063000_add_master_vehicle_route_dashboard.sql',
    ).readAsStringSync();
    final page = File(
      'lib/features/settings/master_operations_dashboard_page.dart',
    ).readAsStringSync();
    final settings =
        File('lib/features/settings/settings_page.dart').readAsStringSync();

    expect(sql, contains('private.is_current_master_admin()'));
    expect(sql, contains('vehicles_total'));
    expect(sql, contains('routes_total'));
    expect(sql, contains('site_chats_archived'));
    expect(sql, contains('No vehicle names'));
    expect(page, contains('個別データは表示しません'));
    expect(page, contains('車両・ルート'));
    expect(page, contains('現場チャット'));
    expect(settings, contains('Master ダッシュボード'));
  });
}
