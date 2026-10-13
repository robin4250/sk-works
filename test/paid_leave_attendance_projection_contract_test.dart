import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('approved paid leave is exposed to attendance without mutating attendance', () {
    final sql = File(
      'supabase/migrations/20260930014500_add_paid_leave_attendance_projection.sql',
    ).readAsStringSync();

    expect(sql, contains('approved_paid_leave_attendance'));
    expect(sql, contains("where r.status = 'approved'"));
    expect(sql, contains('r.leave_date as attendance_date'));
    expect(sql, contains('r.days as paid_leave_days'));
    expect(sql, isNot(contains('insert into public.attendance')));
    expect(sql, isNot(contains('update public.attendance')));
  });
}
