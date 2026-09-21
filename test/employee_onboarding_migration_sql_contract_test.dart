import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('employee onboarding reviewer SQL uses a valid dollar quote', () {
    final sql = File(
      'supabase/migrations/20260922004500_add_employee_onboarding_profile_and_approval.sql',
    ).readAsStringSync();

    final dollar = String.fromCharCode(36);
    final tag = dollar + 'review' + dollar;

    expect(sql, contains('as ' + tag));
    expect(sql, contains(tag + ';'));
    expect(sql, isNot(contains('as ' + dollar + '\n  select exists')));
  });
}
