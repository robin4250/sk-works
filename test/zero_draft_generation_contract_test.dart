import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('attendance creates payroll invoice and subcontractor payment drafts even at zero', () {
    final sql = read(
      'supabase/migrations/20261004104733_allow_zero_draft_generation_and_payment_certificates.sql',
    );

    expect(sql, contains('refresh_automatic_payroll'));
    expect(sql, contains('refresh_automatic_invoice'));
    expect(sql, contains('refresh_automatic_payment_certificate'));
    expect(sql, contains('payment_certificates'));
    expect(sql, contains('partner_payment_settings'));
    expect(sql, contains("coalesce((settings->>(category||'_daily'))::numeric,0)"));
    expect(sql, contains("'設定未入力'"));
    expect(sql, contains('calculation_blocked,calculation_fingerprint'));
  });

  test('generation setting notifications are deduplicated and auto-resolved', () {
    final sql = read(
      'supabase/migrations/20261004105043_dedupe_generation_setting_notifications.sql',
    );

    expect(sql, contains('generation_setting_issues'));
    expect(sql, contains('unique(company_id, issue_key)'));
    expect(sql, contains('upsert_generation_setting_issue'));
    expect(sql, contains('existing_resolved is not null'));
    expect(sql, contains('resolved_at=now()'));
    expect(sql, contains('current_generation_setting_attention'));
    expect(sql, contains('個別給与設定が未入力です'));
    expect(sql, contains('請求方式が未入力です'));
    expect(sql, contains('支払証明書設定が未入力です'));
  });

  test('home attention includes generation setting issue count', () {
    final repository =
        read('lib/features/home/home_attention_repository.dart');

    expect(repository, contains('generationIssueCount'));
    expect(repository, contains('generationIssueMessages'));
    expect(repository, contains('current_generation_setting_attention'));
    expect(
      repository,
      contains('missingCount + paidLeaveApprovalCount + generationIssueCount'),
    );
  });
}
