import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('operational RLS caches auth uid without widening access', () {
    final sql = File(
      'supabase/migrations/20260922045000_cache_auth_uid_in_operational_rls.sql',
    ).readAsStringSync();

    for (final policy in [
      'accessible members can insert chat attachments',
      'authors can delete own chat attachments',
      'accessible members can send sko chat messages',
      'authors can delete own accessible chat messages',
      'authors can update own accessible chat messages',
      'requester or authorized approver can read edit requests',
      'requester or authorized approver can read approvals',
      'worker or people manager can read document statuses',
      'worker or people manager can read document status history',
      'company members can read site worker assignments',
      'managers can manage site worker assignments',
      'worker or attendance manager can create verification',
      'worker or attendance manager can read attendance verifications',
    ]) {
      expect(sql, contains(policy));
    }

    expect(sql, contains('(select auth.uid())'));
    expect(sql, contains('can_approve_daily_report_edits'));
    expect(sql, contains('can_manage_people'));
    expect(sql, contains('can_manage_attendance'));
    expect(sql, isNot(contains('drop policy')));
    expect(sql, isNot(contains('grant ')));
    expect(sql, isNot(contains('revoke ')));
  });
}
