import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('company membership direct reads are self-scoped', () {
    final sql = File(
      'supabase/migrations/20260920224500_restrict_company_members_self_read.sql',
    ).readAsStringSync();

    expect(sql, contains('company_members_self_read'));
    expect(sql, contains('user_id = auth.uid()'));
    expect(sql, isNot(contains('private.has_company_access(company_id)')));
  });
}
