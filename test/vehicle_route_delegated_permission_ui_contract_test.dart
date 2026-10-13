import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('vehicle and route management is not delegated to ordinary members', () {
    final page =
        File('lib/features/people/member_permission_page.dart').readAsStringSync();
    final repository = File(
      'lib/features/operations/vehicle_route_repository.dart',
    ).readAsStringSync();
    final sql = File(
      'supabase/migrations/'
      '20261001232917_restrict_vehicle_route_management_to_management_roles.sql',
    ).readAsStringSync();

    expect(page, isNot(contains("'can_manage_vehicles'")));
    expect(page, isNot(contains("'can_manage_routes'")));
    expect(repository, contains("role == 'owner'"));
    expect(repository, contains("role == 'admin'"));
    expect(repository, contains("role == 'manager'"));
    expect(sql, contains("cm.role::text in ('owner','admin','manager')"));
  });
}
