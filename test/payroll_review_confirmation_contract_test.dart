import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('payroll review confirmation follows statement revision', () {
    final sql = read(
      'supabase/migrations/20261004111000_add_payroll_review_confirmation.sql',
    );
    expect(sql, contains('reviewed_revision'));
    expect(sql, contains('reviewed_revision=p.revision'));
    expect(
      sql,
      contains(
        'reviewed_revision is not null and p.reviewed_revision=p.revision',
      ),
    );
    expect(
      sql,
      contains('全従業員の給与明細を確認してから確定してください'),
    );
  });

  test('manager visibility is configured per worker by administrators', () {
    final sql = read(
      'supabase/migrations/20261004111000_add_payroll_review_confirmation.sql',
    );
    expect(sql, contains('payroll_worker_visibility'));
    expect(sql, contains('visible_to_manager'));
    expect(sql, contains("role_text='manager'"));
    expect(sql, contains("cm.role::text in ('owner','admin')"));
  });

  test('payroll list supports continuous employee review and final confirmation', () {
    final page = read('lib/features/payroll/payroll_review_page.dart');
    expect(page, contains("'給料一覧'"));
    expect(page, contains("'サブ管理者へ見せる従業員'"));
    expect(page, contains("'確認済み'"));
    expect(page, contains("'未確定'"));
    expect(page, contains("'全員確認後に確定'"));
    expect(page, contains('PayrollStatementPreviewPage'));
  });
}
