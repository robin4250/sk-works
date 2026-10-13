import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Master company storage summary returns aggregate distribution only', () {
    final sql = File(
      'supabase/migrations/20260930124500_add_master_storage_company_summary.sql',
    ).readAsStringSync();

    for (final key in <String>[
      'companies_total',
      'companies_with_files',
      'companies_without_files',
      'average_bytes_per_company',
      'max_bytes_per_company',
      'min_bytes_per_company',
      'average_images_per_company',
      'max_images_per_company',
      'average_pdfs_per_company',
      'max_pdfs_per_company',
      'average_attachments_per_company',
      'max_attachments_per_company',
    ]) {
      expect(sql, contains(key));
    }

    expect(sql, contains('public.is_current_user_master_admin()'));
    expect(sql, contains('storage.foldername(name)'));
    expect(sql, contains('from public, anon'));

    for (final forbidden in <String>[
      "'company_id',",
      "'company_name'",
      "'object_name'",
      "'path'",
      "'phone'",
      "'email'",
    ]) {
      expect(sql, isNot(contains(forbidden)));
    }
  });
}
