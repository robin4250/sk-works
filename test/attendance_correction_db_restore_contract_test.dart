import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('attendance correction production restore keeps approval protections', () {
    final sql = File(
      'supabase/migrations/20261003163346_restore_attendance_correction_requests.sql',
    ).readAsStringSync();

    expect(sql, contains('attendance_correction_requests'));
    expect(sql, contains('attendance_correction_items'));
    expect(sql, contains('enable row level security'));
    expect(sql, contains('submit_attendance_correction_request'));
    expect(sql, contains('decide_attendance_correction_request'));
    expect(sql, contains('company_approval_assignees'));
    expect(sql, contains('to authenticated'));
  });
}
