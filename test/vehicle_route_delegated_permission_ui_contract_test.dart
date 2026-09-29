import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('vehicle and route delegated permissions are editable with confirmation', () {
    final page =
        File('lib/features/people/member_permission_page.dart').readAsStringSync();
    final repository = File(
      'lib/features/people/member_permission_repository.dart',
    ).readAsStringSync();
    final sql = File(
      'supabase/migrations/20260930062000_add_vehicle_route_permission_rows.sql',
    ).readAsStringSync();

    expect(page, contains("'can_manage_vehicles': '車両の登録・変更・休止'"));
    expect(page, contains("'can_manage_routes': 'ルートの登録・変更・休止'"));
    expect(page, contains('権限変更の確認'));
    expect(page, contains('変更を確定'));

    expect(
      repository,
      contains("rpc('company_member_vehicle_route_permission_rows')"),
    );
    expect(repository, contains("'can_manage_vehicles'"));
    expect(repository, contains("'can_manage_routes'"));

    expect(sql, contains('company_member_vehicle_route_permission_rows'));
    expect(sql, contains("in ('owner','admin','manager') then true"));
    expect(sql, contains('p.can_manage_vehicles'));
    expect(sql, contains('p.can_manage_routes'));
    expect(sql, contains('grant execute'));

    final effectiveSql = File(
      'supabase/migrations/20260930062500_fix_manager_vehicle_route_effective_permissions.sql',
    ).readAsStringSync();
    expect(
      effectiveSql,
      contains("'can_manage_vehicles',v_role='manager' or coalesce"),
    );
    expect(
      effectiveSql,
      contains("'can_manage_routes',v_role='manager' or coalesce"),
    );
  });
}
