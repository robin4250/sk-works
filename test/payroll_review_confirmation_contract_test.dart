import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('payroll review confirmation follows statement revision', () {
    final foundation = read(
      'supabase/migrations/20261004110609_add_payroll_review_confirmation.sql',
    );
    final confirmation = read(
      'supabase/migrations/20261004111520_confirm_payroll_review_month.sql',
    );

    expect(foundation, contains('payroll_statement_reviews'));
    expect(foundation, contains('checked_revision=ps.revision'));
    expect(foundation, contains('confirmed_revision=ps.revision'));
    expect(foundation, contains('review_confirmed'));
    expect(confirmation, contains('r.checked_revision=ps.revision'));
    expect(
      confirmation,
      contains('全従業員の給与明細を確認してから確定してください'),
    );
  });

  test('manager visibility is configured per worker by administrators', () {
    final sql = read(
      'supabase/migrations/20261004110609_add_payroll_review_confirmation.sql',
    );
    expect(sql, contains('payroll_manager_worker_visibility'));
    expect(sql, contains('visible_to_manager'));
    expect(sql, contains("role_text='manager'"));
    expect(sql, contains("role_text not in ('owner','admin')"));
    expect(sql, contains('set_payroll_manager_worker_visibility'));
  });

  test('payroll list persists checks and final month confirmation', () {
    final repository =
        read('lib/features/payroll/payroll_review_repository.dart');
    final page = read('lib/features/payroll/payroll_review_page.dart');

    expect(repository, contains("'payroll_review_workspace'"));
    expect(repository, contains("'set_payroll_review_check'"));
    expect(repository, contains("'confirm_payroll_review_month'"));
    expect(repository, contains("'set_payroll_manager_worker_visibility'"));
    expect(page, contains("'給料一覧'"));
    expect(page, contains("'サブ管理者へ見せる従業員'"));
    expect(page, contains("'確認済み'"));
    expect(page, contains("'未確定'"));
    expect(page, contains("'全員確認後に確定'"));
    expect(page, contains('PayrollStatementPreviewPage'));
  });
}
