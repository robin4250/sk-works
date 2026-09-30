import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Master dashboard compares 7, 30 and 90 day usage snapshots', () {
    final repository = File(
      'lib/features/settings/master_operations_dashboard_repository.dart',
    ).readAsStringSync();
    final page = File(
      'lib/features/settings/master_operations_dashboard_page.dart',
    ).readAsStringSync();

    expect(repository, contains("'usageComparison'"));
    expect(repository, contains("params: {'p_days': 7}"));
    expect(repository, contains("params: {'p_days': 30}"));
    expect(repository, contains("params: {'p_days': 90}"));

    expect(page, contains("'期間比較（7日・30日・90日）'"));
    expect(page, contains("'events_total'"));
    expect(page, contains("'companies_active'"));
    expect(page, contains("'users_active'"));
  });
}
