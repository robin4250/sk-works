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

    expect(page, contains("label: const Text('控除項目を追加')"));
    expect(page, contains("values['custom_deductions'] = customDeductions"));
    expect(page, contains('追加控除${index + 1} 名称'));
    expect(page, contains('追加控除${index + 1} 金額'));
    expect(migration, contains('custom_deductions jsonb'));
    expect(migration, contains('payroll_custom_deductions_guard'));
  });

  test('payroll PDF renders configured and payroll-adjustment deductions', () {
    final pdf = read('lib/features/payroll/payroll_pdf_service.dart');
    final adjustmentMigration = read(
      'supabase/migrations/'
      '20260929203000_sync_payroll_adjustments_into_statements.sql',
    );

    expect(pdf, contains('_configuredDeductionEntries'));
    expect(pdf, contains("detail['custom_deductions']"));
    expect(pdf, contains('overflowDeductionGroups'));
    expect(pdf, contains('customDeductions.entries'));
    expect(
      adjustmentMigration,
      contains("when direction = 'deduction' then amount_yen"),
    );
    expect(
      adjustmentMigration,
      contains("else -amount_yen"),
    );
  });

  test('payment certificate settings verify save and preview same PDF', () {
    final page =
        read('lib/features/payroll/payment_certificates_page.dart');
    final repository =
        read('lib/features/payroll/payment_certificate_repository.dart');

    expect(page, contains("label: Text("));
    expect(page, contains("'プレビュー'"));
    expect(page, contains('_preview'));
    expect(
      page,
      contains('PaymentCertificatePreviewPage(record: record)'),
    );
    expect(repository, contains("'save_partner_payment_setting'"));
    expect(repository, contains("'partner_payment_settings_workspace'"));
    expect(repository, contains('final refreshed = await loadSettings()'));
    expect(repository, contains('previewForSetting'));
    expect(repository, contains("siteName: '設定プレビュー'"));
  });

  test('payment certificate settings are available to management roles', () {
    final app = read('lib/app_v2.dart');
    final migration = read(
      'supabase/migrations/'
      '20261006143007_payment_certificate_settings_management_access.sql',
    );

    final keyIndex = app.indexOf("key: 'payment_certificate_settings'");
    expect(keyIndex, greaterThan(0));
    final nearby = app.substring(keyIndex - 180, keyIndex + 420);
    expect(nearby, contains('_identity.isManagement'));
    expect(nearby, contains('管理者・サブ管理者'));
    expect(migration, contains("'owner','admin','manager'"));
  });
}
