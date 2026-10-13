import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('invoice settings expose subject contact and payment due text', () {
    final repository = read(
      'lib/features/invoices/invoice_settings_repository.dart',
    );
    final page = read('lib/features/invoices/invoice_settings_page.dart');

    expect(repository, contains('invoiceSubject'));
    expect(repository, contains('invoiceContactName'));
    expect(repository, contains('paymentDueText'));
    expect(repository, contains("rpc('invoice_document_settings')"));
    expect(repository, contains("'save_invoice_settings_v2'"));
    expect(repository, contains("'save_invoice_branding'"));
    expect(repository, contains('companyLogoBase64'));
    expect(repository, contains('companySealBase64'));

    expect(page, contains("'件名'"));
    expect(page, contains("'請求書の承認者'"));
    expect(page, contains("'支払約定日'"));
    expect(page, contains("'請求元（会社データから自動反映）'"));
    expect(page, contains("'ロゴ画像を登録'"));
  });

  test(
    'invoice PDF uses month-end date counter company data and branding images',
    () {
      final pdf = read('lib/features/invoices/invoice_pdf_service.dart');

      expect(pdf, contains("'請　求　書'"));
      expect(pdf, contains('size: 20'));
      expect(pdf, contains("align: pw.TextAlign.center"));
      expect(pdf, contains("invoice.invoiceNumber"));
      expect(pdf, contains('_monthEnd(invoice)'));
      expect(pdf, contains('_workPeriod(invoice)'));
      expect(pdf, contains('settings?.invoiceSubject'));
      expect(pdf, contains('settings?.companyAddress'));
      expect(pdf, contains('settings?.companyPhone'));
      expect(pdf, contains('_datedApprovalStamp'));
      expect(pdf, contains('CompanySealPdf.build('));
      expect(pdf, contains('CompanySealPdf.build('));
      expect(
        File('lib/features/shared/company_seal_pdf.dart').readAsStringSync(),
        contains("companyName.trim()"),
      );
      expect(
        File('lib/features/shared/company_seal_pdf.dart').readAsStringSync(),
        contains("name.endsWith('株式会社')"),
      );
      expect(pdf, contains("settings?.companyName ?? ''"));
      expect(pdf, contains('box(316, 80,'));
      expect(pdf, isNot(contains("final shown = sealText.isEmpty ? '会社之印'")));
      expect(pdf, contains('CompanySealPdf.build('));
      expect(pdf, isNot(contains('companySealImage')));
      expect(pdf, contains('settings?.paymentDueText'));
      expect(pdf, contains("'A4を画面幅に合わせて表示します。プレビュー上で拡大・縮小できます。'"));
    },
  );

  test('invoice number assignment is company-scoped and automatic', () {
    final sql = read(
      'supabase/migrations/20261005072500_invoice_number_stamps_and_terms.sql',
    );

    expect(sql, contains('private.invoice_number_counters'));
    expect(sql, contains('assign_invoice_number_and_issue_date'));
    expect(sql, contains('new.invoice_number'));
    expect(sql, contains('new.issue_date := new.billing_period_end'));
    expect(sql, contains('invoice_document_settings'));
    expect(sql, contains('save_invoice_settings_v2'));
    expect(
      sql,
      contains('revoke all on function public.invoice_document_settings()'),
    );
  });

  test('invoice site rows use the adopted seven columns and stored snapshot rows', () {
    final pdf = read('lib/features/invoices/invoice_pdf_service.dart');
    final repository = read(
      'lib/features/invoices/invoice_cloud_repository.dart',
    );
    final sql = read(
      'supabase/migrations/20261005133000_invoice_site_breakdown_rows.sql',
    );

    for (final label in [
      'No.',
      '現場名',
      '工事内容・摘要',
      '期間',
      '人数',
      '単価（円）',
      '金額（円）',
    ]) {
      expect(pdf, contains("'$label'"));
    }
    expect(repository, contains("invoice['snapshot']"));
    expect(repository, contains("line['site_label']"));
    expect(repository, contains("line['work_content']"));
    expect(repository, contains("'通常作業'"));
    expect(pdf, contains('line.siteLabel.trim().isNotEmpty'));
    expect(pdf, contains('line.displayWorkContent'));
    expect(
      read('lib/domain/invoice_engine.dart'),
      contains('String get displayWorkContent'),
    );
    expect(sql, contains("'work_content','夜間作業'"));
    expect(sql, contains("'work_content','（手当て）'"));
    expect(sql, contains("'work_content','（残業）'"));
    expect(sql, contains("'work_content','（法定福利費）'"));
    expect(sql, contains("'work_content','（消費税）'"));
    expect(sql, contains('*1.5'));
    expect(pdf, contains('content: _displayLineLabel(line, site)'));
    final latest = read(
      'supabase/migrations/20261005152000_invoice_allowance_and_early_rows.sql',
    );
    expect(latest, contains("'work_content','（手当て）'"));
    expect(latest, contains("'work_content','（早出）'"));
    expect(latest, contains("'work_content','（残業）'"));
    expect(latest, contains('early_amount'));
    expect(latest, contains('a+b+early_amount+c'));
    expect(latest, contains('group by allowance_name'));
  });

  test('invoice model and repository carry number and billing dates', () {
    final model = read('lib/domain/invoice_engine.dart');
    final repository = read(
      'lib/features/invoices/invoice_cloud_repository.dart',
    );

    expect(model, contains('invoiceNumber'));
    expect(model, contains('issueDate'));
    expect(model, contains('periodStart'));
    expect(model, contains('periodEnd'));

    expect(repository, contains('invoice_number'));
    expect(repository, contains('issue_date'));
    expect(repository, contains('billing_period_end'));
  });
}
