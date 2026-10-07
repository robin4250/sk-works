import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('recent device regressions stay fixed together', () {
    final prereg = read(
      'supabase/migrations/20261006193110_activate_preregistered_employees.sql',
    );
    final invite = read('supabase/functions/create-employee-invite/index.ts');
    final personnel = read(
      'supabase/migrations/20261006192517_worker_personnel_approvers_one_to_three.sql',
    );
    final approvalsHub =
        read('lib/features/approvals/approvals_hub_page.dart');
    final siteApprovals =
        read('lib/features/sites/site_information_approvals_page.dart');
    final payrollTarget = read(
      'supabase/migrations/20261006190922_payroll_adjustment_latest_statement_period.sql',
    );
    final payrollPdf = read('lib/features/payroll/payroll_pdf_service.dart');
    final invoicePreview =
        read('lib/features/invoices/invoice_pdf_service.dart');

    // Employees registered with name + phone must be management-visible before
    // first-login linkage, and the invite flow must not hide them again.
    expect(prereg, contains("'active'"));
    expect(prereg, contains("status='inactive'"));
    expect(prereg, contains('user_id is null'));
    expect(invite, contains('status: "active"'));
    expect(invite, isNot(contains('status: "inactive"')));

    // Personnel changes use a configurable 1-3 approver workflow.
    expect(personnel, contains('worker_personnel_approvers'));
    expect(personnel, contains('between 1 and 3'));
    expect(personnel, contains('required_approvals'));
    expect(personnel, contains('v_count>=v_required'));

    // Site information/completion requests must be reachable from 承認待ち.
    expect(approvalsHub, contains("'現場データの承認待ち'"));
    expect(approvalsHub, contains('SiteInformationApprovalsPage'));
    expect(siteApprovals, contains('loadInformationRequests'));
    expect(siteApprovals, contains('reviewInformationRequest'));

    // Payroll adjustments target an existing payslip period and deductions are
    // rendered both for fixed names and freeform adjustment labels.
    expect(payrollTarget, contains('payroll_adjustment_latest_statement_period'));
    expect(payrollTarget, contains('order by ps.period_end desc'));
    expect(payrollPdf, contains("MapEntry<String, Object?>('道具代'"));
    expect(payrollPdf, contains('final adjustmentDeductions = _customMoneyEntries'));
    expect(payrollPdf, contains('...adjustmentDeductions.entries.map('));

    // Invoice preview must rely on PdfPreview sizing instead of reintroducing
    // the outer InteractiveViewer that made the A4 content effectively vanish.
    expect(invoicePreview, contains('class _ExactInvoiceScreen'));
    expect(invoicePreview, contains('_ScreenDetailTable(rows:rows)'));
    expect(
      invoicePreview,
      isNot(contains('transformationController: _zoomController')),
    );
  });
}
