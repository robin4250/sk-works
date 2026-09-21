import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/home/home_membership_repository.dart';

void main() {
  test('sub-admin is management but not a full admin', () {
    const subAdmin = HomeIdentity(
      role: 'manager',
      companyName: 'SKO',
      displayName: 'Sub Admin',
    );

    expect(subAdmin.isAdmin, isFalse);
    expect(subAdmin.isSubAdmin, isTrue);
    expect(subAdmin.isManagement, isTrue);
    expect(subAdmin.can('can_view_invoices'), isFalse);
    expect(subAdmin.can('can_view_admin_site_data'), isFalse);
  });

  test('owner and admin remain full admins', () {
    const owner = HomeIdentity(
      role: 'owner',
      companyName: 'SKO',
      displayName: 'Owner',
    );
    const admin = HomeIdentity(
      role: 'admin',
      companyName: 'SKO',
      displayName: 'Admin',
    );

    expect(owner.isAdmin, isTrue);
    expect(admin.isAdmin, isTrue);
    expect(owner.isManagement, isTrue);
    expect(admin.isManagement, isTrue);
  });

  test('sub-admin keeps management home and payroll menu', () {
    final home =
        File('lib/features/home/friendly_home_content.dart').readAsStringSync();
    final app = File('lib/app_v2.dart').readAsStringSync();

    expect(home, contains('if (identity.isManagement)'));
    expect(
      app,
      contains(
        "if (!_isAdmin)\n"
        "        const _MenuAction(\n"
        "          key: 'payroll',",
      ),
    );
    expect(
      app,
      contains("if (_identity.can('can_approve_daily_report_edits'))"),
    );
  });
}
