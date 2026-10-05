import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('invoice confirmers are configurable up to two registered users', () {
    final page = read('lib/features/invoices/invoice_settings_page.dart');
    final repo = read('lib/features/invoices/invoice_approval_repository.dart');
    final sql = read(
      'supabase/migrations/20261005081500_invoice_approval_workflow.sql',
    );

    expect(page, contains("'請求書の承認者'"));
    expect(page, contains("'確認者は1～2名で設定してください'"));
    expect(page, contains("'確認者は最大2名です'"));
    expect(repo, contains("'invoice_approver_rows'"));
    expect(repo, contains("'set_invoice_approvers'"));
    expect(sql, contains('position between 1 and 3'));
    expect(sql, contains('approver must be a registered company user'));
    expect(sql, contains("cm.role::text='owner'"));
  });

  test('invoice approval is audited and final only after every approver', () {
    final sql = read(
      'supabase/migrations/20261005081500_invoice_approval_workflow.sql',
    );

    expect(sql, contains('invoice_approval_audit'));
    expect(sql, contains("'approved'"));
    expect(sql, contains("status<>'approved'"));
    expect(sql, contains('approval_finalized_at'));
    expect(sql, contains("'invoice_approval'"));
    expect(sql, contains("'月末の請求書を確認して承認してください。'"));
  });

  test('notification opens the target invoice directly', () {
    final notifications =
        read('lib/features/notifications/notifications_page.dart');
    final invoicePage =
        read('lib/features/invoices/invoice_cloud_page.dart');

    expect(notifications, contains("item.actionKey == 'invoice_approval'"));
    expect(notifications, contains('initialInvoiceId: item.actionId'));
    expect(invoicePage, contains('this.initialInvoiceId'));
    expect(invoicePage, contains('invoice.invoiceId == widget.initialInvoiceId'));
  });

  test('invoice PDF keeps original recipient underline alignment', () {
    final pdf = read('lib/features/invoices/invoice_pdf_service.dart');

    expect(pdf, contains('alignment: pw.Alignment.center'));
    expect(pdf, contains("invoice.customerId"));
    expect(pdf, contains("alignment: pw.Alignment.centerRight"));
    expect(pdf, contains("'御中'"));
    expect(pdf, contains('pw.BorderSide(color: blue, width: 1.4)'));
  });

  test('invoice PDF uses approval boxes and stamp A B behavior', () {
    final pdf = read('lib/features/invoices/invoice_pdf_service.dart');

    expect(pdf, contains("'確認者'"));
    expect(pdf, contains('_approvalBoxes('));
    expect(pdf, contains('designB: visible[i].position.isEven'));
    expect(pdf, contains("visible[i].approved"));
    expect(pdf, contains("'確認印'"));
    expect(pdf, contains('_companySeal('));
    expect(pdf, contains('_memoryImage('));
    expect(pdf, contains('companySealImage'));
    expect(pdf, contains('companyLogo'));
    expect(pdf, contains('pw.Positioned('));
  });

  test('invoice and payroll previews support pinch zoom pan and reset', () {
    final invoice = read('lib/features/invoices/invoice_pdf_service.dart');
    final payroll =
        read('lib/features/payroll/payroll_statements_page.dart');

    for (final source in [invoice, payroll]) {
      expect(source, contains('InteractiveViewer('));
      expect(source, contains('TransformationController'));
      expect(source, contains('minScale: 1'));
      expect(source, contains('maxScale: 5'));
      expect(source, contains('panEnabled: true'));
      expect(source, contains('scaleEnabled: true'));
      expect(source, contains('Matrix4.identity()'));
    }
  });

  test('preview print and share keep the same PDF builders', () {
    final invoice = read('lib/features/invoices/invoice_pdf_service.dart');
    final payroll =
        read('lib/features/payroll/payroll_statements_page.dart');

    expect(invoice, contains('InvoicePdfService.buildPdf('));
    expect(invoice, contains('Printing.layoutPdf('));
    expect(invoice, contains('Printing.sharePdf('));
    expect(payroll, contains('PayrollPdfService.buildPdf(statement)'));
    expect(payroll, contains('allowPrinting: true'));
    expect(payroll, contains('allowSharing: true'));
  });
}
