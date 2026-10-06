import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('individual payroll settings support unlimited named deductions', () {
    final page =
        read('lib/features/payroll/individual_payroll_settings_page.dart');
    final migration = read(
      'supabase/migrations/20261006142713_payroll_custom_deductions.sql',
    );

    expect(page, contains('控除項目を追加'));
    expect(page, contains('_customDeductions.add'));
    expect(page, contains("values['custom_deductions']"));
    expect(page, contains('追加控除\${index + 1} 名称'));
    expect(migration, contains('custom_deductions jsonb'));
    expect(migration, contains('apply_payroll_custom_deductions'));
  });

  test('payroll PDF renders configured and payroll-adjustment deductions', () {
    final pdf = read('lib/features/payroll/payroll_pdf_service.dart');
    final statementSync = read(
      'supabase/migrations/'
      '20260929203000_sync_payroll_adjustments_into_statements.sql',
    );

    expect(pdf, contains('_configuredDeductionEntries'));
    expect(pdf, contains("detail['custom_deductions']"));
    expect(pdf, contains('_customMoneyEntries(detail, direction: -1)'));
    expect(pdf, contains('overflowDeductionGroups'));
    expect(statementSync, contains("direction = 'deduction'"));
    expect(statementSync, contains('else -amount_yen'));
  });

  test('payment certificate settings use RPC save and verified reload', () {
    final repository =
        read('lib/features/payroll/payment_certificate_repository.dart');
    final migration = read(
      'supabase/migrations/'
      '20261006142141_payment_certificate_settings_rpc.sql',
    );

    expect(repository, contains("'partner_payment_settings_workspace'"));
    expect(repository, contains("'save_partner_payment_setting'"));
    expect(repository, contains('final refreshed = await loadSettings()'));
    expect(migration, contains('private.save_partner_payment_setting'));
    expect(migration, contains('grant execute on function public.save_partner_payment_setting'));
  });

  test('payment certificate settings expose preview using same PDF builder', () {
    final page =
        read('lib/features/payroll/payment_certificates_page.dart');
    final repository =
        read('lib/features/payroll/payment_certificate_repository.dart');

    expect(page, contains("label: const Text('プレビュー')"));
    expect(page, contains('PaymentCertificatePreviewPage(record: record)'));
    expect(repository, contains('previewForSetting'));
    expect(
      page,
      contains('build: (_) => PaymentCertificatePdfService.buildPdf(record)'),
    );
  });

  test('sub-admin management role can reach payment certificate settings', () {
    final app = read('lib/app_v2.dart');
    final migration = read(
      'supabase/migrations/'
      '20261006143007_payment_certificate_settings_management_access.sql',
    );

    expect(app, contains("key: 'payment_certificate_settings'"));
    expect(app, contains("accessLabel: SkoLanguageController.tr('管理者・サブ管理者')"));
    expect(migration, contains("'owner','admin','manager'"));
  });
}
