import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LINE binding rows are only visible to owner/admin', () {
    final sql = File(
      'supabase/migrations/20260920225500_restrict_line_binding_visibility.sql',
    ).readAsStringSync();

    expect(sql, contains('owners and admins can read line bindings'));
    expect(sql, contains("'owner'::app_role"));
    expect(sql, contains("'admin'::app_role"));
    expect(sql, isNot(contains('company members can read line bindings')));
  });
}
