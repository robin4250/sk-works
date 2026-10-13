import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('high-use foreign keys have non-destructive covering indexes', () {
    final sql = File(
      'supabase/migrations/20260922041000_index_high_use_foreign_keys_v2.sql',
    ).readAsStringSync();

    for (final indexName in [
      'app_notifications_company_id_idx',
      'attendance_entries_created_by_idx',
      'attendance_entries_updated_by_idx',
      'attendance_verification_settings_updated_by_idx',
      'attendance_verifications_created_by_idx',
      'daily_report_edit_requests_requested_by_idx',
      'daily_reports_created_by_idx',
      'daily_reports_updated_by_idx',
      'document_requirements_company_template_id_idx',
    ]) {
      expect(sql, contains('create index if not exists $indexName'));
    }

    expect(sql, isNot(contains('drop index')));
    expect(sql, isNot(contains('drop table')));
    expect(sql, isNot(contains('delete from')));
  });
}
