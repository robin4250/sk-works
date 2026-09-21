import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('employee onboarding reviewer SQL uses a valid dollar quote', () {
    final sql = File(
      'supabase/migrations/20260922004500_add_employee_onboarding_profile_and_approval.sql',
    ).readAsStringSync();

    expect(sql, contains(r'as $review$'));
    expect(sql, contains(r'$review$;'));
    expect(sql, isNot(contains('as $\n  select exists')));
  });
}
