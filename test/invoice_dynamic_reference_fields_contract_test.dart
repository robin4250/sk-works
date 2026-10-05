import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('invoice settings expose subject contact and payment due text', () {
    final repository =
        read('lib/features/invoices/invoice_settings_repository.dart');
    final page = read('lib/features/invoices/invoice_settings_page.dart');

    expect(repository, contains('invoiceSubject'));
    expect(repository, contains('invoiceContactName'));
    expect(repository, contains('paymentDueText'));
    expect(repository, contains("rpc('invoice_document_settings')"));
    expect(repository, contains("'save_invoice_settings_v2'"));

    expect(page, contains("'件名'"));
    expect(page, contains("'担当者名（確認印）'"));
    expect(page, contains("'支払約定日'"));
    expect(page, contains("'請求元（会社データから自動反映）'"));
  });

  test('invoice PDF uses month-end date counter company data and generated stamps', () {
    final pdf = read('lib/features/invoices/invoice_pdf_service.dart');

    expect(pdf, contains("'御　請　求　書'"));
    expect(pdf, contains('textAlign: pw.TextAlign.center'));
    expect(pdf, contains("'請求書番号：\${invoice.invoiceNumber}'"));
    expect(pdf, contains('_monthEnd(invoice)'));
    expect(pdf, contains('_workPeriod(invoice)'));
    expect(pdf, contains('settings?.invoiceSubject'));
    expect(pdf, contains('settings?.companyAddress'));
    expect(pdf, contains('settings?.companyPhone'));
    expect(pdf, contains('_confirmationStamp('));
    expect(pdf, contains('_companySeal('));
    expect(pdf, contains('settings?.paymentDueText'));
    expect(pdf, contains("'ピンチ操作で拡大・縮小できます'"));
  });

  test('invoice number assignment is company-scoped and automatic', () {
    final sql = read(
      'supabase/migrations/20261005072500_invoice_number_stamps_and_terms.sql',
    );

    expect(sql, contains('private.invoice_number_counters'));
    expect(sql, contains("~ '^[0-9]+\\$'"));
    expect(sql, contains('greatest('));
    expect(sql, contains('assign_invoice_number_and_issue_date'));
    expect(sql, contains('new.invoice_number'));
    expect(sql, contains('new.issue_date := new.billing_period_end'));
    expect(sql, contains('invoice_document_settings'));
    expect(sql, contains('save_invoice_settings_v2'));
    expect(
      sql,
      contains(
        'revoke all on function public.invoice_document_settings()',
      ),
    );
  });

  test('invoice model and repository carry number and billing dates', () {
    final model = read('lib/domain/invoice_engine.dart');
    final repository =
        read('lib/features/invoices/invoice_cloud_repository.dart');

    expect(model, contains('invoiceNumber'));
    expect(model, contains('issueDate'));
    expect(model, contains('periodStart'));
    expect(model, contains('periodEnd'));

    expect(repository, contains('invoice_number'));
    expect(repository, contains('issue_date'));
    expect(repository, contains('billing_period_end'));
  });
}
