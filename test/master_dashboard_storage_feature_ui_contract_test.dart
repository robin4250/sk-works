import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Master dashboard shows aggregate storage distribution and feature states', () {
    final repository = File(
      'lib/features/settings/master_operations_dashboard_repository.dart',
    ).readAsStringSync();
    final page = File(
      'lib/features/settings/master_operations_dashboard_page.dart',
    ).readAsStringSync();

    expect(repository, contains("'get_master_storage_company_summary'"));
    expect(repository, contains("'get_master_feature_usage_status'"));
    expect(repository, contains("'storageCompany'"));
    expect(repository, contains("'featureUsage'"));

    expect(page, contains("'会社ストレージ分布'"));
    expect(page, contains("'平均使用量 MB'"));
    expect(page, contains("'最大使用量 MB'"));
    expect(page, contains("'機能利用状態'"));
    expect(page, contains("'有効・未使用'"));
    expect(page, contains("'有効・使用あり'"));
    expect(page, contains("'制御対象機能'"));

    for (final forbidden in <String>[
      'company_id',
      'company_name',
      'object_name',
      'file_path',
      'user_id',
    ]) {
      expect(page, isNot(contains(forbidden)));
    }
  });
}

