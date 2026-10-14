import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/domain/invoice_engine.dart';
import 'package:sk_works/features/invoices/invoice_pdf_service.dart';
import 'package:sk_works/features/invoices/invoice_settings_repository.dart';
import 'package:sk_works/features/payroll/payment_certificate_pdf_service.dart';
import 'package:sk_works/features/payroll/payment_certificate_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('actual invoice and certificate show four totals without duplicate charges', () async {
    final output = Directory(Platform.environment['SKO_FOUR_TOTALS_OUTPUT']!)..createSync(recursive: true);
    final font = pw.Font.ttf(ByteData.sublistView(File('assets/fonts/company-seal/NotoSansJP-Bold.ttf').readAsBytesSync()));
    final invoice = InvoiceEngine.calculate(customerId: '取引先', billingPeriod: '2026年10月',
      detailMode: InvoiceDetailMode.siteBreakdownOnInvoice, sites: [
        SiteInvoiceCalculation.fromSavedDetails(siteId: 'a', siteName: '現場A', welfareRateBps: 1500,
          subtotalYen: 37720, lines: const [
            InvoiceLine(label: '通常作業', quantity: 1, unitPriceYen: 32800),
            InvoiceLine(label: '（福利厚生費）', quantity: 0, unitPriceYen: 0, amountYenOverride: 4920),
            InvoiceLine(label: '（消費税）', quantity: 0, unitPriceYen: 0, amountYenOverride: 3772),
          ]),
      ], subtotalYenOverride: 37720, taxYenOverride: 3772, grandTotalYenOverride: 41492);
    final invoiceBytes = await InvoicePdfService.buildPdf([invoice], regularFont: font, boldFont: font,
      settings: const InvoiceSettingsData(companyName: '自社', taxRate: 10, welfareRate: 15,
        templateTitle: '請求書', footerNote: '', bankName: '', bankBranch: '', bankAccountType: '',
        bankAccountNumber: '', bankAccountHolder: '', companySealEnabled: false));
    File('${output.path}/invoice.pdf').writeAsBytesSync(invoiceBytes);
    final certificate = PaymentCertificateRecord(id: 'preview', partnerCompanyName: '下請会社',
      periodStart: DateTime(2026, 10), periodEnd: DateTime(2026, 10, 31),
      grossAmount: 41492, deductions: 1000, netAmount: 40492, status: 'preview', revision: 1,
      payerCompanyName: '自社', payerCompanySealEnabled: false, lines: const [
        PaymentCertificateLine(siteName: '現場A', workContent: '通常作業', quantityLabel: '1', unitPriceYen: 32800, amountYen: 32800),
        PaymentCertificateLine(siteName: '〃', workContent: '（福利厚生費）', quantityLabel: '', unitPriceYen: 0, amountYen: 4920),
        PaymentCertificateLine(siteName: '〃', workContent: '（消費税）', quantityLabel: '', unitPriceYen: 0, amountYen: 3772),
      ]);
    File('${output.path}/certificate.pdf').writeAsBytesSync(await PaymentCertificatePdfService.buildPdf(
      certificate, regularFont: font, boldFont: font));
    expect(invoice.grandTotalYen, 41492);
    expect(certificate.netAmount, 40492);
  }, skip: Platform.environment['SKO_FOUR_TOTALS_OUTPUT'] == null ? 'Opt-in rendered PDF proof.' : false);
}
