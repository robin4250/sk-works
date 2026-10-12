import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/domain/expense_cost_snapshot.dart';
import 'package:sk_works/domain/invoice_engine.dart';
import 'package:sk_works/features/expenses/expense_claim.dart';
import 'package:sk_works/features/expenses/expense_detail_pdf.dart';
import 'package:sk_works/features/expenses/expense_document_repository.dart';
import 'package:sk_works/features/invoices/invoice_pdf_service.dart';
import 'package:sk_works/features/invoices/invoice_settings_repository.dart';
import 'package:sk_works/features/payroll/payment_certificate_repository.dart';
import 'package:sk_works/features/payroll/payment_certificate_pdf_service.dart';
import 'expense_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Map<String, dynamic> snapshot({int amount = 1234}) => {
    'expense_extra_source_version': 1,
    'expense_extra_amount_yen': amount,
    'expense_extra_claims': [
      {'id': 'charged', 'revision': 1, 'amount_yen': 1234},
    ],
  };
  test('explicit expense snapshots reject duplicates and inconsistent amounts', () {
    expect(ExpenseCostSnapshot.parse({'expense_extra_amount_yen': 1234}).amountYen, 0);
    expect(() => ExpenseCostSnapshot.parse(snapshot(amount: 1235)), throwsStateError);
    final duplicate = snapshot();
    duplicate['expense_extra_claims'].add(duplicate['expense_extra_claims'].first);
    expect(() => ExpenseCostSnapshot.parse(duplicate), throwsStateError);
    final cost = ExpenseCostSnapshot.parse(snapshot());
    expect(cost.amountYen, 1234);
    expect(() => cost.claims.add({}), throwsUnsupportedError);
    expect(() => cost.claims.first['amount_yen'] = 1, throwsUnsupportedError);
    expect(() => cost.verifyDetails([{'id': 'other', 'revision': 1, 'amount_yen': 1234}]), throwsStateError);
    expect(() => cost.verifyDetails([{'id': 'charged', 'revision': 2, 'amount_yen': 1234}]), throwsStateError);
  });
  test('invoice adds the original expense after welfare and tax only once', () {
    final result = InvoiceEngine.calculate(
      customerId: '取引先', billingPeriod: '2026年10月',
      detailMode: InvoiceDetailMode.siteBreakdownOnInvoice,
      sites: [SiteInvoiceCalculation(siteId: 'site', siteName: '現場', welfareRateBps: 800,
        lines: [const InvoiceLine(label: '作業', quantity: 1, unitPriceYen: 10000)])],
      taxRateBps: 1000, expenseCost: ExpenseCostSnapshot.parse(snapshot()),
    );
    expect(result.subtotalYen, 10800);
    expect(result.taxYen, 1080);
    expect(result.grandTotalYen, 13114);
    expect(InvoicePdfService.buildTextSnapshot([result]), contains('別途経費（原額）'));
    final saved = InvoiceEngine.calculate(customerId: '取引先', billingPeriod: '2026年10月',
      detailMode: InvoiceDetailMode.siteBreakdownOnInvoice, sites: [],
      expenseCost: result.expenseCost, subtotalYenOverride: 10800,
      taxYenOverride: 1080, grandTotalYenOverride: 13114);
    expect(saved.grandTotalYen, 13114);
  });
  test('real invoice and payment PDFs retain original tax and a charged detail page', () async {
    final fontBytes = await rootBundle.load('assets/fonts/company-seal/NotoSansJP-Bold.ttf');
    pw.Font font() => pw.Font.ttf(fontBytes);
    final out = Directory('build/expense-cost-documents-proof')..createSync(recursive: true);
    final cost = ExpenseCostSnapshot.parse(snapshot());
    ExpenseDocumentDetails details(ExpenseDocument kind) {
      final category = kind == ExpenseDocument.invoice ? ExpenseCategory.customer : ExpenseCategory.subcontractor;
      return ExpenseDocumentDetails(kind: kind, documentId: 'doc', subjectId: 'party',
        month: DateTime(2026, 10), costRecoveryAmountYen: 1234,
        claims: ExpenseClaims(companyId: 'company', claims: [expenseFixture('charged',
          status: ExpenseApproval.approved, amount: 1234, description: '検証交通費',
          allocation: ExpenseAllocation(category, counterpartyId: 'party'))]));
    }
    const settings = InvoiceSettingsData(companyName: '検証会社', taxRate: 10, welfareRate: 8,
      templateTitle: '請求書', footerNote: '', bankName: '', bankBranch: '', bankAccountType: '',
      bankAccountNumber: '', bankAccountHolder: '', companySealEnabled: false);
    for (final expenseOnly in [false, true]) {
      final label = expenseOnly ? 'only' : 'with_work';
      final subtotal = expenseOnly ? 0 : 21600, tax = expenseOnly ? 0 : 2160;
      final total = subtotal + tax + 1234;
      final invoice = InvoiceCalculationResult(customerId: '検証取引先', invoiceId: 'doc',
        billingPeriod: '2026年10月', periodStart: DateTime(2026, 10),
        detailMode: InvoiceDetailMode.siteBreakdownOnInvoice, taxRateBps: 1000, expenseCost: cost,
        siteCalculations: expenseOnly ? [] : [SiteInvoiceCalculation(siteId: 'site', siteName: '検証現場', welfareRateBps: 800,
          lines: [const InvoiceLine(label: '通常作業', quantity: 1, unitPriceYen: 20000)])],
        subtotalYenOverride: subtotal, taxYenOverride: tax, grandTotalYenOverride: total);
      final payment = PaymentCertificateRecord(id: 'doc', partnerCompanyName: '検証下請け', partnerCompanyId: 'party',
        periodStart: DateTime(2026, 10), periodEnd: DateTime(2026, 11, 0), grossAmount: total,
        deductions: 0, netAmount: total, status: 'draft', revision: 1, payerCompanySealEnabled: false,
        expenseCost: cost, lines: expenseOnly ? [] : [
          const PaymentCertificateLine(siteName: '検証現場', workContent: '通常作業', quantityLabel: '1', unitPriceYen: 20000, amountYen: 20000),
          const PaymentCertificateLine(siteName: '検証現場', workContent: '福利厚生費', quantityLabel: '', unitPriceYen: 0, amountYen: 1600),
          const PaymentCertificateLine(siteName: '検証現場', workContent: '消費税', quantityLabel: '', unitPriceYen: 0, amountYen: 2160),
        ]);
      File('${out.path}/invoice_$label.pdf').writeAsBytesSync(await InvoicePdfService.buildPdf([invoice],
        settings: settings, regularFont: font(), boldFont: font(), approvalsByInvoice: const {'doc': []},
        expenseDetailsByInvoice: {'doc': details(ExpenseDocument.invoice)}));
      File('${out.path}/payment_$label.pdf').writeAsBytesSync(await PaymentCertificatePdfService.buildPdf(payment,
        regularFont: font(), boldFont: font(), expenseDetails: details(ExpenseDocument.paymentCertificate)));
      await expectLater(InvoicePdfService.buildPdf([invoice], settings: settings,
        regularFont: font(), boldFont: font(), approvalsByInvoice: const {'doc': []},
        expenseDetailsByInvoice: {'doc': ExpenseDocumentDetails(kind: ExpenseDocument.invoice,
          documentId: 'doc', subjectId: 'party', month: DateTime(2026, 10),
          costRecoveryAmountYen: 999, claims: details(ExpenseDocument.invoice).claims)}), throwsStateError);
    }
  });
}
