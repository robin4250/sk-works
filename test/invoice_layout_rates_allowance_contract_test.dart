import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('invoice approval and amount frames are separate and due amount widths match', () {
    final pdf = read('lib/features/invoices/invoice_pdf_service.dart');

    expect(pdf, contains('box(316, 80,'));
    expect(pdf, contains('box(384.2756, 749.8898,'));
    expect(pdf, contains('104, 31'));
    expect(pdf, contains("'約定日'"));
    expect(pdf, contains("'金額（円）'"));
  });

  test('invoice uses generated company and surname-only approval seals', () {
    final pdf = read('lib/features/invoices/invoice_pdf_service.dart');
    expect(pdf, contains('_datedApprovalStamp'));
    expect(pdf, contains("record.stampRole == 'approval' ? '承認' : '確認'"));
    expect(pdf, contains('record.stampSurname'));
    expect(pdf, contains('CompanySealPdf.build('));
    expect(
      File('lib/features/shared/company_seal_pdf.dart').readAsStringSync(),
      contains("name.endsWith('株式会社')"),
    );
  });

  test('admin site financials have invoice-specific overtime and early rates', () {
    final page = read('lib/features/sites/admin_site_financial_page.dart');
    final repo = read(
      'lib/features/sites/admin_site_financial_repository.dart',
    );
    final migration = read(
      'supabase/migrations/'
      '20261006140454_invoice_billing_overtime_early_and_allowance_labels.sql',
    );

    expect(page, contains("'請求書用 自動計算'"));
    expect(page, contains("'残業'"));
    expect(page, contains("'早出'"));
    expect(page, contains('式:'));
    expect(repo, contains('billingOvertimeHourRateYen'));
    expect(repo, contains('billingEarlyHourRateYen'));
    expect(repo, contains("'billing_overtime_hour_rate_yen'"));
    expect(repo, contains("'billing_early_hour_rate_yen'"));
    expect(migration, contains('billing_overtime_hour_rate_yen'));
    expect(migration, contains('billing_early_hour_rate_yen'));
  });

  test('invoice allowance rows expose the actual allowance name', () {
    final cloud = read('lib/features/invoices/invoice_cloud_repository.dart');
    final migration = read(
      'supabase/migrations/'
      '20261006140454_invoice_billing_overtime_early_and_allowance_labels.sql',
    );

    expect(cloud, contains("line['allowance_name']"));
    expect(cloud, contains("'（\$allowanceName）'"));
    expect(migration, contains("'work_content','（'||allowance_cfg.name||'）'"));
  });

  test(
    'existing invoice time rates are backfilled before separate editing',
    () {
      final migration = read(
        'supabase/migrations/'
        '20261006140524_backfill_invoice_billing_time_rates.sql',
      );

      expect(migration, contains('coalesce(overtime_hour_rate_yen,0)'));
      expect(migration, contains('coalesce(early_hour_rate_yen,0)'));
    },
  );
}
