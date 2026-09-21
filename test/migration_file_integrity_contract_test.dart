import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('migration integrity check protects required hardening points', () {
    final source = File('tool/check_migration_files.sh').readAsStringSync();

    expect(source, contains('migration version重複'));
    expect(source, contains('20260919010000_reconcile_chat_line_schema.sql'));
    expect(source, contains('20260920213500_revoke_anon_public_table_access.sql'));
    expect(source, contains('20260920224500_restrict_company_members_self_read.sql'));
    expect(source, contains('20260920225500_restrict_line_binding_visibility.sql'));
  });
}
