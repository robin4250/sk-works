import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Master recovery email function is fail-closed and never returns codes', () {
    final source = File(
      'supabase/functions/send-master-recovery-codes/index.ts',
    ).readAsStringSync();

    expect(source, contains('RESEND_API_KEY'));
    expect(source, contains('MASTER_RECOVERY_FROM_EMAIL'));
    expect(source, contains('authentication required'));
    expect(source, contains('service_create_master_recovery_challenge'));
    expect(source, contains('Promise.allSettled'));
    expect(source, contains('challengeId'));
    expect(source, contains('expiresAt'));
    expect(source, isNot(contains('primaryCode,')));
    expect(source, isNot(contains('secondaryCode,')));
    expect(source, isNot(contains('primaryEmail,')));
    expect(source, isNot(contains('secondaryEmail,')));
    expect(source, isNot(contains('console.log')));
  });

  test('Master recovery challenge issuance is database rate-limited', () {
    final sql = File(
      'supabase/migrations/20260930113000_rate_limit_master_recovery_issuance.sql',
    ).readAsStringSync();

    expect(sql, contains("interval '10 minutes'"));
    expect(sql, contains('v_recent_count >= 3'));
    expect(sql, contains('master recovery challenge rate limit exceeded'));
    expect(sql, contains('before insert on private.master_recovery_challenges'));
  });
}
