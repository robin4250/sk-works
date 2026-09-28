import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('employee payroll statements include active payroll adjustments', () {
    final sql = read(
      'supabase/migrations/20260929203000_sync_payroll_adjustments_into_statements.sql',
    );

    expect(sql, contains('my_payroll_statement_rows_with_adjustments'));
    expect(sql, contains('a.cancelled_at is null'));
    expect(sql, contains("direction = 'addition'"));
    expect(sql, contains("direction = 'deduction'"));
    expect(sql, contains('jsonb_object_agg'));
    expect(sql, contains('w.user_id = v_user_id'));
  });

  test('payroll statement repository uses adjustment-aware RPC', () {
    final repository =
        read('lib/features/payroll/payroll_statement_repository.dart');

    expect(
      repository,
      contains("rpc(\n      'my_payroll_statement_rows_with_adjustments'"),
    );
    expect(repository, contains("row['company_name']"));
    expect(repository, contains("row['worker_name']"));
  });

  test('payroll statement UI and PDF format numeric adjustment details as yen', () {
    final page = read('lib/features/payroll/payroll_statements_page.dart');
    final pdf = read('lib/features/payroll/payroll_pdf_service.dart');

    expect(page, contains('_formatDetailValue(entry.value)'));
    expect(pdf, contains('_detailValue(entry.value)'));
  });
}
