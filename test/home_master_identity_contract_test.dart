import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Master identity is independent from company admin permissions', () {
    final source = File(
      'lib/features/home/home_membership_repository.dart',
    ).readAsStringSync();

    expect(source, contains('final bool isMasterAdmin;'));
    expect(source, contains("current_master_admin_status"));
    expect(source, contains("masterStatus['is_master_admin'] == true"));
    expect(source, contains("if (isMasterAdmin) return 'Master';"));
    expect(
      source,
      contains('bool get isManagement => isMasterAdmin || isAdmin || isSubAdmin;'),
    );

    // Master status must not grant tenant/company permissions by itself.
    expect(
      source,
      contains("if (role == 'owner' || role == 'admin') return true;"),
    );
    expect(
      source,
      isNot(contains('if (isMasterAdmin) return true;')),
    );
  });

  test('Master identity survives missing company membership', () {
    final source = File(
      'lib/features/home/home_membership_repository.dart',
    ).readAsStringSync();

    final masterCheck = source.indexOf("current_master_admin_status");
    final membershipRead = source.indexOf(".from('company_members')");
    final emptyMembership = source.indexOf('if (rows.isEmpty)');
    final preservedMaster = source.indexOf(
      'isMasterAdmin: isMasterAdmin,',
      emptyMembership,
    );

    expect(masterCheck, greaterThanOrEqualTo(0));
    expect(membershipRead, greaterThan(masterCheck));
    expect(emptyMembership, greaterThan(membershipRead));
    expect(preservedMaster, greaterThan(emptyMembership));
  });
}
