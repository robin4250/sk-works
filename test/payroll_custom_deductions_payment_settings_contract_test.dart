import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('individual payroll settings support freely named custom deductions', () {
    final page =
        read('lib/features/payroll/individual_payroll_settings_page.dart');
    final migration = read(
      'supabase/migrations/20261006141922_payroll_custom_deductions.sql',
    );

    expect(page, contains("'控除項目を追加'"));
    expect(page, contains("'追加控除\${i + 1} 名称'"));
    expect(page, contains("values['custom_deductions']"));
    expect(migration, contains('custom_deductions jsonb'));
    expect(migration, contains('v_custom_deductions'));
    expect(migration, contains('v_custom_deduction_detail'));
  });

  test('payroll PDF renders all custom and adjustment deductions', () {
    final pdf = read('lib/features/payroll/payroll_pdf_service.dart');
    final adjustmentContract =
        read('test/payroll_adjustment_statement_sync_contract_test.dart');

    expect(pdf, contains('allExtraDeductions'));
    expect(pdf, contains('overflowDeductions'));
    expect(pdf, contains("'控除 続き'"));
    expect(pdf, contains('_customMoneyEntries(detail, direction: -1)'));
    expect(
      adjustmentContract,
      contains('my_payroll_statement_rows_with_adjustments'),
    );
  });

  test('payment certificate settings use guarded RPCs and same PDF preview', () {
    final repository =
        read('lib/features/payroll/payment_certificate_repository.dart');
    final page =
        read('lib/features/payroll/payment_certificates_page.dart');
    final migration = read(
      'supabase/migrations/20261006142141_payment_certificate_settings_rpc.sql',
    );

    expect(repository, contains("'partner_payment_settings_workspace'"));
    expect(repository, contains("'save_partner_payment_setting'"));
    expect(repository, isNot(contains("from('partner_payment_settings').upsert")));
    expect(page, contains("'支払証明書プレビュー'"));
    expect(page, contains('PaymentCertificatePreviewPage('));
    expect(
      page,
      contains('PaymentCertificatePdfService.buildPdf(record)'),
    );
    expect(migration, contains('private.current_company_admin_id()'));
    expect(
      migration,
      contains('grant execute on function public.save_partner_payment_setting'),
    );
  });
}
