import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home identity preserves membership role when enrichment fails', () {
    final source =
        File('lib/features/home/home_membership_repository.dart').readAsStringSync();

    final roleRead = source.indexOf(
      "final role = rows.first['role']?.toString() ?? 'viewer';",
    );
    final featureRpc = source.indexOf(
      "await _client.rpc('current_feature_permissions')",
    );
    final payrollRpc = source.indexOf(
      "await _client.rpc('current_payroll_adjustment_permissions')",
    );
    final returnIdentity = source.indexOf(
      'return HomeIdentity(\n      role: role,',
    );

    expect(roleRead, greaterThanOrEqualTo(0));
    expect(featureRpc, greaterThan(roleRead));
    expect(payrollRpc, greaterThan(roleRead));
    expect(returnIdentity, greaterThan(featureRpc));
    expect(returnIdentity, greaterThan(payrollRpc));

    expect(
      source,
      contains('optional home\n    // enrichment must never downgrade'),
    );
    expect(
      source,
      contains('Feature permission enrichment must not erase the membership role.'),
    );
    expect(
      source,
      contains('Payroll permission enrichment must not erase the membership role.'),
    );
  });
}
