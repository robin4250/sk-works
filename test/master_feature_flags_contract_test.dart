import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('master feature flags expose only optional product capabilities', () {
    final source =
        File('lib/features/settings/master_feature_flags.dart').readAsStringSync();

    for (final optional in <String>[
      'paidLeave',
      'qualifications',
      'documents',
      'vehicleManagement',
      'routeAssignment',
      'expenseClaims',
    ]) {
      expect(source, contains(optional));
    }

    for (final core in <String>['auth', 'security', 'attendance']) {
      expect(source, isNot(contains('  $core,')));
    }
  });

  test('feature disable is reversible instead of destructive', () {
    final source =
        File('lib/features/settings/master_feature_flags.dart').readAsStringSync();

    expect(source, contains('bool isEnabled('));
    expect(source, contains('MasterFeatureFlags withEnabled('));
    expect(source, contains('next.remove(feature)'));
    expect(source, contains('next.add(feature)'));
  });
}
