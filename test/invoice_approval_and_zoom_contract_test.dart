import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test(
    'invoice confirmers are configurable from one to three registered users',
    () {
      final page = read('lib/features/invoices/invoice_settings_page.dart');
      final repo = read(
        'lib/features/invoices/invoice_approval_repository.dart',
      );
      final sql = read(
        'supabase/migrations/20261005081500_invoice_approval_workflow.sql',
      );

      expect(page, contains("'請求書の承認者'"));
      expect(page, contains("'承認者は1～3名で設定してください'"));
      expect(page, contains("'承認者は最大3名です'"));
      expect(repo, contains("'invoice_approver_rows'"));
      expect(repo, contains("'set_invoice_approvers'"));
      expect(sql, contains('position between 1 and 3'));
      final latest = read(
        'supabase/migrations/20261007221757_invoice_stamp_policy_and_approval_history.sql',
      );
      expect(latest, contains('invoice approvers must contain 1 to 3 users'));
      expect(sql, contains('approver must be a registered company user'));
      expect(sql, contains("cm.role::text='owner'"));
    },
  );

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
    final notifications = read(
      'lib/features/notifications/notifications_page.dart',
    );
    final invoicePage = read('lib/features/invoices/invoice_cloud_page.dart');

    expect(notifications, contains("'invoice_approval' =>"));
    expect(notifications, contains('initialInvoiceId: item.actionId'));
    expect(invoicePage, contains('this.initialInvoiceId'));
    expect(
      invoicePage,
      contains('invoice.invoiceId == widget.initialInvoiceId'),
    );
  });

  test('invoice PDF keeps adopted v8 recipient panel and A4 geometry', () {
    final pdf = read('lib/features/invoices/invoice_pdf_service.dart');
    expect(pdf, contains('box(28, 80, 266, 96)'));
    expect(pdf, contains('invoice.customerId'));
    expect(pdf, contains('御中'));
    expect(pdf, contains('margin: pw.EdgeInsets.zero'));
    expect(pdf, contains('box(316, 80,'));
    expect(pdf, contains('const gridBottom = 669.8898'));
  });

  test('invoice stamps use explicit roles and immutable audit dates', () {
    final pdf = read('lib/features/invoices/invoice_pdf_service.dart');
    final migration = read(
      'supabase/migrations/20261007221757_invoice_stamp_policy_and_approval_history.sql',
    );
    expect(pdf, contains('確 認 印'));
    expect(pdf, contains('approvals[i].approved'));
    expect(pdf, contains("record.stampRole == 'approval' ? '承認' : '確認'"));
    expect(pdf, contains('record.stampDisplayDate'));
    expect(pdf, contains('CompanySealPdf.build('));
    expect(pdf, isNot(contains('companySealImage')));
    expect(pdf, isNot(contains('record.approvedAt ?? DateTime.now()')));
    expect(migration, contains('display_date_override'));
    expect(migration, contains('invoice_stamp_date_mode'));
    expect(migration, contains('stamp_role text'));
    expect(migration, contains('cancel_invoice_approval'));
    expect(migration, contains('invoice_approval_audit'));
    expect(pdf, contains('for (var i = 0; i < 3; i++)'));
  });

  test(
    'invoice preview uses the exact shared PDF bytes while payroll keeps zoom',
    () {
      final invoice = read('lib/features/invoices/invoice_pdf_service.dart');
      final payroll = read('lib/features/payroll/payroll_statements_page.dart');
      expect(invoice, contains('child: _InvoicePdfZoomView('));
      expect(invoice, contains('Printing.raster(widget.pdfBytes, dpi: 120)'));
      expect(invoice, isNot(contains('child: _ExactInvoiceScreen(')));
      expect(invoice, contains("'A4を画面幅に合わせて表示します。プレビュー上で拡大・縮小できます。'"));
      expect(payroll, contains('InteractiveViewer('));
      expect(payroll, contains('TransformationController'));
      expect(payroll, contains('minScale: 1'));
      expect(payroll, contains('maxScale: 5'));
    },
  );

  test('preview print and share keep the same PDF builders', () {
    final invoice = read('lib/features/invoices/invoice_pdf_service.dart');
    final payroll = read('lib/features/payroll/payroll_statements_page.dart');

    expect(invoice, contains('InvoicePdfService.buildPdf('));
    expect(invoice, contains('Printing.layoutPdf('));
    expect(invoice, contains('Printing.sharePdf('));
    expect(payroll, contains('PayrollPdfService.buildPdf(statement)'));
    expect(payroll, contains('allowPrinting: true'));
    expect(payroll, contains('allowSharing: true'));
  });

  test('invoice screen preview renders the complete shared PDF output', () {
    final invoice = read('lib/features/invoices/invoice_pdf_service.dart');
    expect(invoice, contains('InvoicePdfService.buildPdf('));
    expect(invoice, contains('Printing.raster(widget.pdfBytes, dpi: 120)'));
    expect(invoice, contains('minScale: 1'));
    expect(invoice, contains('maxScale: 5'));
    expect(invoice, isNot(contains('child: _ExactInvoiceScreen(')));
  });
}
