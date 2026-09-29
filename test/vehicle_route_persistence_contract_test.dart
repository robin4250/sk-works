import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('vehicle and route persistence is company scoped and soft-disable only', () {
    final sql = File(
      'supabase/migrations/20260930061000_add_vehicle_route_persistence.sql',
    ).readAsStringSync();

    expect(sql, contains('create table if not exists public.vehicles'));
    expect(sql, contains('create table if not exists public.route_assignments'));
    expect(sql, contains('is_active boolean not null default true'));
    expect(sql, contains('revoke delete on public.vehicles'));
    expect(sql, contains('revoke delete on public.route_assignments'));
    expect(sql, isNot(contains('create policy "authorized members can delete')));
  });

  test('all company members can view while delegated permissions control writes', () {
    final sql = File(
      'supabase/migrations/20260930061000_add_vehicle_route_persistence.sql',
    ).readAsStringSync();

    expect(sql, contains('company members can view vehicles'));
    expect(sql, contains('company members can view route assignments'));
    expect(sql, contains('can_manage_vehicles'));
    expect(sql, contains('can_manage_routes'));
    expect(sql, contains("role_name in ('owner','admin','manager')"));
  });

  test('route company scope validates vehicle, site, and driver', () {
    final sql = File(
      'supabase/migrations/20260930061000_add_vehicle_route_persistence.sql',
    ).readAsStringSync();

    expect(sql, contains('validate_route_assignment_company_scope'));
    expect(sql, contains('vehicle must belong to the same company'));
    expect(sql, contains('site must belong to the same company'));
    expect(sql, contains('driver must belong to the same company'));
  });

  test('route domain exposes soft-active state', () {
    final source = File('lib/domain/route_assignment.dart').readAsStringSync();
    expect(source, contains('this.isActive = true'));
    expect(source, contains('final bool isActive'));
  });
}
