import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('core high-use foreign keys have dedicated indexes', () {
    final sql = File(
      'supabase/migrations/20260922030000_add_core_foreign_key_indexes.sql',
    ).readAsStringSync();

    for (final marker in [
      'attendance_entries(site_id)',
      'attendance_entries(worker_id)',
      'daily_reports(site_id)',
      'daily_report_edit_requests(report_id)',
      'daily_report_edit_approvals(approver_user_id)',
      'company_approval_assignees(user_id)',
      'employee_registration_invites(worker_id)',
      'employee_registration_invites(created_by)',
      'employee_registration_invites(approved_by)',
      'employee_registration_invites(replace_approval_assignee_user_id)',
      'invoices(customer_id)',
      'chat_attachments(message_id)',
    ]) {
      expect(sql, contains(marker));
    }

    expect(sql, isNot(contains('drop index')));
    expect(sql, isNot(contains('drop table')));
    expect(sql, isNot(contains('alter table')));
  });
}
