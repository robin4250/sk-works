import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bulk attendance correction keeps original and proposed snapshots', () {
    final sql = File(
      'supabase/migrations/20260929210000_add_attendance_correction_requests.sql',
    ).readAsStringSync();

    expect(sql, contains('attendance_correction_requests'));
    expect(sql, contains('attendance_correction_items'));
    expect(sql, contains('original_snapshot'));
    expect(sql, contains('proposed_snapshot'));
    expect(sql, contains('change_summary'));
  });

  test('bulk correction submission requires one shared signature', () {
    final sql = File(
      'supabase/migrations/20260929210000_add_attendance_correction_requests.sql',
    ).readAsStringSync();

    expect(sql, contains('submit_attendance_correction_request'));
    expect(sql, contains('p_signer_name'));
    expect(sql, contains('p_signature_json'));
    expect(sql, contains("status = 'submitted'"));
    expect(sql, contains('signed_at = now()'));
  });

  test('only attendance managers can build correction requests', () {
    final sql = File(
      'supabase/migrations/20260929210000_add_attendance_correction_requests.sql',
    ).readAsStringSync();

    expect(sql, contains('can_manage_attendance_corrections'));
    expect(sql, contains("'can_manage_attendance'"));
    expect(sql, contains("cm.role::text in ('owner','admin')"));
    expect(sql, contains("cm.role::text = 'manager'"));
  });

  test('configured approver decides and approved changes are applied atomically', () {
    final sql = File(
      'supabase/migrations/20260929210000_add_attendance_correction_requests.sql',
    ).readAsStringSync();

    expect(sql, contains('pending_attendance_correction_rows'));
    expect(sql, contains('attendance_correction_item_rows'));
    expect(sql, contains('decide_attendance_correction_request'));
    expect(sql, contains('company_approval_assignees'));
    expect(sql, contains("p_decision not in ('approve','reject')"));
    expect(sql, contains("set status = 'approved'"));
    expect(sql, contains('update public.attendance_entries'));
    expect(sql, contains('requester cannot approve own request'));
  });
}
