import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('vehicle and route grants exclude anon and unnecessary privileges', () {
    final sql = File(
      'supabase/migrations/20260930090000_harden_vehicle_route_table_grants.sql',
    ).readAsStringSync();

    expect(sql, contains('revoke all on table public.vehicles from anon'));
    expect(sql, contains('revoke all on table public.route_assignments from anon'));
    expect(sql, contains('delete, truncate, references, trigger'));
    expect(sql, contains('grant select, insert, update on table public.vehicles'));
    expect(
      sql,
      contains('grant select, insert, update on table public.route_assignments'),
    );
  });
}
