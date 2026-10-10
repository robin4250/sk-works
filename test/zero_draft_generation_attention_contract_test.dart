import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('attendance creates zero-value payroll and invoice drafts when settings are missing', () {
    final migration = read(
      'supabase/migrations/20261004104733_allow_zero_draft_generation_and_payment_certificates.sql',
    );

    expect(migration, contains('refresh_automatic_payroll'));
    expect(migration, contains('coalesce((settings->>(category||\'_daily\'))::numeric,0)'));
    expect(migration, contains('automatic_calculation,calculation_blocked'));
    expect(migration, contains('refresh_automatic_invoice'));
    expect(migration, contains("'設定未入力'"));
    expect(migration, contains('payment_certificates'));
    expect(migration, contains('attendance_refresh_payment_certificate_trigger'));
  });

  test('generation setting attention is deduplicated and auto-resolved', () {
    final migration = read(
      'supabase/migrations/20261004105043_dedupe_generation_setting_notifications.sql',
    );

    expect(migration, contains('generation_setting_issues'));
    expect(migration, contains('unique(company_id, issue_key)'));
    expect(migration, contains('upsert_generation_setting_issue'));
    expect(migration, contains('existing_resolved is not null'));
    expect(migration, contains('resolved_at=now()'));
    expect(migration, contains('current_generation_setting_attention'));
  });

  test('home attention count includes generation setting issues', () {
    final repository = read(
      'lib/features/home/home_attention_repository.dart',
    );

    expect(repository, contains('generationIssueCount'));
    expect(repository, contains('generationIssueMessages'));
    final center = read(
      'lib/features/notifications/attention_center_repository.dart',
    );
    expect(repository, contains('AttentionCenterRepository'));
    expect(repository, contains('await _repository.load()'));
    expect(repository, contains('data.snapshot.unresolvedCount'));
    expect(center, contains('current_generation_setting_attention'));
    expect(center, contains('mapGenerationAttention'));
    expect(
      repository,
      contains('missingCount + paidLeaveApprovalCount + generationIssueCount'),
    );
  });
}
