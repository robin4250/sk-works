import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('paid leave foundation protects balances and approval state', () {
    final migration = File(
      'supabase/migrations/20260929234500_add_paid_leave_foundation.sql',
    ).readAsStringSync();

    expect(migration, contains('create table if not exists public.paid_leave_balances'));
    expect(migration, contains('create table if not exists public.paid_leave_requests'));
    expect(migration, contains("status in ('pending','approved','rejected','cancelled')"));
    expect(migration, contains('check (used_days <= granted_days)'));
    expect(migration, contains('alter table public.paid_leave_balances enable row level security'));
    expect(migration, contains('alter table public.paid_leave_requests enable row level security'));
  });
}
