import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/domain/invoice_engine.dart';
import 'package:sk_works/features/expenses/expense_claim.dart';
import 'package:sk_works/features/expenses/expense_detail_pdf.dart';
import 'package:sk_works/features/expenses/expense_document_repository.dart';
import 'package:sk_works/features/payroll/payroll_statement_repository.dart';
import 'package:sk_works/features/payroll/payroll_pdf_service.dart';
import 'package:sk_works/features/payroll/payment_certificate_repository.dart';
import 'package:sk_works/features/payroll/payment_certificate_pdf_service.dart';
import 'package:sk_works/features/invoices/invoice_pdf_service.dart';
import 'package:sk_works/features/invoices/invoice_settings_repository.dart';
import 'expense_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'real document generators put expense details after page one without changing totals',
    () async {
      final bytes = await rootBundle.load(
        'assets/fonts/company-seal/NotoSansJP-Bold.ttf',
      );
      final out = Directory('build/expense-documents-proof')
        ..createSync(recursive: true);
      const settings = InvoiceSettingsData(
        companyName: '試験会社',
        taxRate: 10,
        welfareRate: 0,
        templateTitle: '請求書',
        footerNote: '',
        bankName: '',
        bankBranch: '',
        bankAccountType: '',
        bankAccountNumber: '',
        bankAccountHolder: '',
        companySealEnabled: false,
      );
      final claims = ExpenseClaims(
        companyId: 'company',
        claims: [
          expenseFixture(
            'APPROVED',
            status: ExpenseApproval.approved,
            allocation: ExpenseAllocation(
              ExpenseCategory.customer,
              counterpartyId: 'customer',
              counterpartyName: '試験取引先',
            ),
          ),
          expenseFixture(
            'PENDING',
            status: ExpenseApproval.pending,
            allocation: ExpenseAllocation(
              ExpenseCategory.subcontractor,
              counterpartyId: 'partner',
              counterpartyName: '試験下請け',
            ),
          ),
          expenseFixture('REJECTED', status: ExpenseApproval.rejected),
        ],
      );
      ExpenseDocumentDetails details(ExpenseDocument kind, String subject) =>
          ExpenseDocumentDetails(
            kind: kind,
            documentId: 'doc',
            subjectId: subject,
            month: DateTime(2026, 10),
            claims: claims,
          );
      final statement = PayrollStatementRecord(
        id: 'doc',
        companyName: '試験会社',
        workerName: '試験社員',
        periodStart: DateTime(2026, 10, 1),
        periodEnd: DateTime(2026, 10, 31),
        grossPay: 10000,
        deductions: 1000,
        netPay: 9000,
        detail: {
          'company_seal_enabled': false,
          'custom_earnings': [
            for (var i = 0; i < 20; i++) {'name': '手当$i', 'amount_yen': 100},
          ],
        },
      );
      final payment = PaymentCertificateRecord(
        id: 'doc',
        partnerCompanyName: '試験下請け',
        partnerCompanyId: 'partner',
        periodStart: DateTime(2026, 10, 1),
        periodEnd: DateTime(2026, 10, 31),
        grossAmount: 10000,
        deductions: 1000,
        netAmount: 9000,
        status: 'draft',
        revision: 1,
        payerCompanySealEnabled: false,
      );
      final invoice = InvoiceCalculationResult(
        invoiceId: 'doc',
        customerId: '試験取引先',
        billingPeriod: '2026年10月',
        detailMode: InvoiceDetailMode.siteBreakdownOnInvoice,
        siteCalculations: [],
        taxRateBps: 1000,
        subtotalYenOverride: 10000,
        taxYenOverride: 1000,
        grandTotalYenOverride: 11000,
        periodStart: DateTime(2026, 10, 1),
      );
      for (final withDetails in [false, true]) {
        pw.Font font() => pw.Font.ttf(bytes);
        final label = withDetails ? 'with' : 'original';
        File('${out.path}/payroll_$label.pdf').writeAsBytesSync(
          await PayrollPdfService.buildPdf(
            statement,
            regularFont: font(),
            boldFont: font(),
            expenseDetails: withDetails
                ? details(ExpenseDocument.payroll, 'worker-a')
                : null,
          ),
        );
        File('${out.path}/payment_$label.pdf').writeAsBytesSync(
          await PaymentCertificatePdfService.buildPdf(
            payment,
            regularFont: font(),
            boldFont: font(),
            expenseDetails: withDetails
                ? details(ExpenseDocument.paymentCertificate, 'partner')
                : null,
          ),
        );
        File('${out.path}/invoice_$label.pdf').writeAsBytesSync(
          await InvoicePdfService.buildPdf(
            [invoice],
            settings: settings,
            regularFont: font(),
            boldFont: font(),
            approvalsByInvoice: const {'doc': []},
            expenseDetailsByInvoice: withDetails
                ? {'doc': details(ExpenseDocument.invoice, 'customer')}
                : null,
          ),
        );
      }
      expect(statement.netPay, 9000);
      expect(payment.netAmount, 9000);
      expect(invoice.grandTotalYen, 11000);
    },
  );
  test(
    'document envelope rejects foreign company, wrong month and stale revision',
    () {
      final v = {
        'kind': 'payroll',
        'document_id': 'doc',
        'company_id': 'company',
        'subject_id': 'worker',
        'month': '2026-10-01',
        'revision': 2,
        'claims': <dynamic>[],
      };
      expect(
        () => ExpenseDocumentDetails.parse(
          v,
          ExpenseDocument.payroll,
          'other',
          DateTime(2026, 10),
        ),
        throwsStateError,
      );
      expect(
        () => ExpenseDocumentDetails.parse(
          v,
          ExpenseDocument.payroll,
          'doc',
          DateTime(2026, 9),
        ),
        throwsStateError,
      );
      expect(
        () => ExpenseDocumentDetails.parse(
          v,
          ExpenseDocument.payroll,
          'doc',
          DateTime(2026, 10),
          revision: 1,
        ),
        throwsStateError,
      );
    },
  );
}
