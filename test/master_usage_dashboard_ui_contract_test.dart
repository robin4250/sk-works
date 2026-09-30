import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Master dashboard shows aggregate usage rankings only', () {
    final page = File(
      'lib/features/settings/master_operations_dashboard_page.dart',
    ).readAsStringSync();
    final repository = File(
      'lib/features/settings/master_operations_dashboard_repository.dart',
    ).readAsStringSync();

    expect(repository, contains("'get_master_usage_snapshot'"));
    expect(repository, contains("'p_days': usageDays"));
    expect(page, contains("'usage'"));
    expect(page, contains('7日'));
    expect(page, contains('30日'));
    expect(page, contains('90日'));
    expect(page, contains('よく使われる操作'));
    expect(page, contains('よく開かれる画面'));
    expect(page, contains('よく使われる機能'));
    expect(page, contains('まだ集計データがありません'));

    for (final forbidden in <String>[
      'user_id',
      'company_id',
      'chat_messages',
      'workers.phone',
      'latitude',
      'longitude',
    ]) {
      expect(page, isNot(contains(forbidden)));
    }
  });
}
