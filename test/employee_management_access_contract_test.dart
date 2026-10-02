import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('employee pages are limited to admin and sub-admin roles', () {
    final app = File('lib/app_v2.dart').readAsStringSync();
    final repository = File(
      'lib/features/people/people_cloud_repository.dart',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/20261002011817_add_employee_personnel_rows.sql',
    ).readAsStringSync();

    expect(app, contains("key == 'people' && !_identity.isManagement"));
    expect(
      app,
      contains("'社員情報は管理者・サブ管理者のみ利用できます'"),
    );
    expect(repository, contains("member.role == 'owner'"));
    expect(repository, contains("member.role == 'admin'"));
    expect(repository, contains("member.role == 'manager'"));
    expect(
      migration,
      contains("cm.role::text in ('owner','admin','manager')"),
    );
  });
}
