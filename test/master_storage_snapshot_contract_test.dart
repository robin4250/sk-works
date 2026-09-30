import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Master storage snapshot is aggregate-only and Master-gated', () {
    final sql = File(
      'supabase/migrations/20260930101000_add_master_storage_snapshot.sql',
    ).readAsStringSync();
    final repository = File(
      'lib/features/settings/master_operations_dashboard_repository.dart',
    ).readAsStringSync();
    final page = File(
      'lib/features/settings/master_operations_dashboard_page.dart',
    ).readAsStringSync();

    for (final key in <String>[
      'objects_total',
      'bytes_total',
      'buckets_with_objects',
      'images_total',
      'pdfs_total',
    ]) {
      expect(sql, contains(key));
    }

    expect(sql, contains('public.is_current_user_master_admin()'));
    expect(sql, contains('from public, anon'));
    expect(sql, contains('No object names, paths, file contents'));
    expect(repository, contains("'get_master_storage_snapshot'"));
    expect(repository, contains("'storage'"));
    expect(page, contains("'ストレージ'"));
    expect(page, contains("'使用量 MB'"));
    expect(page, contains("'使用中バケット'"));
  });

  test('Master storage snapshot does not return identifying storage fields', () {
    final sql = File(
      'supabase/migrations/20260930101000_add_master_storage_snapshot.sql',
    ).readAsStringSync();

    expect(sql, isNot(contains("'object_name'")));
    expect(sql, isNot(contains("'bucket_id'")));
    expect(sql, isNot(contains("'company_id'")));
    expect(sql, isNot(contains("'user_id'")));
  });
}
