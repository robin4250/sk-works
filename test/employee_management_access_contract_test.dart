import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('employee pages permit read-only viewers while management writes remain restricted', () {
    final app = File('lib/app_v2.dart').readAsStringSync();
    final repository = File(
      'lib/features/people/people_cloud_repository.dart',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/20261002011817_add_employee_personnel_rows.sql',
    ).readAsStringSync();

    expect(app, contains("key == 'people' && !_identity.isManagement && !_isViewer"));
    expect(
      app,
      contains("'社員情報は管理者・閲覧者・サブ管理者が閲覧できます'"),
    );
    expect(repository, contains("member.role == 'viewer'"));
    expect(repository, contains("await _requireManagePeople();"));
    expect(repository, contains("'employee_personnel_view'"));
    expect(repository, contains("member.role == 'owner'"));
    expect(repository, contains("member.role == 'admin'"));
    expect(repository, contains("member.role == 'manager'"));
    expect(
      migration,
      contains("cm.role::text in ('owner','admin','manager')"),
    );
  });
}
