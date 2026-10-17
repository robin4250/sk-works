import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/features/invoices/invoice_order_acceptance_pdf.dart';
import 'package:sk_works/features/invoices/invoice_pdf_service.dart';
import 'package:sk_works/domain/invoice_engine.dart';
import 'package:sk_works/features/invoices/invoice_settings_repository.dart';
import 'package:sk_works/features/shared/company_seal_pdf.dart';
import 'package:sk_works/features/shared/trade_document_attachment.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TradeDocumentAttachment attachment({String date = '2026-10-16', bool long = false}) =>
    TradeDocumentAttachment.fromJson({
      'version': 1,
      'payload': {
        'version': 1, 'kind': 'acceptance', 'month': '2026-10',
        'order_date': '2026-10-15', 'issue_date': date,
        if (long) 'work_name': List.filled(20, '鳶工・安全設備・足場工事').join(),
        if (long) 'acceptance_text': '乙は、貴殿から受領した2026年10月15日付の注文書記載の条件通り、本工事を請け負うことを承諾いたします。${List.filled(30, '追加条件を確認します。').join()}',
        'issuer': {
          'name': long ? List.filled(20, '株式会社受注').join() : '株式会社受注',
          'address': long ? List.filled(40, '東京都千代田区').join().substring(0, 240) : '神奈川県横浜市2-2-2',
          'corporate_number': '9876543210987',
          'representative_name': long ? List.filled(40, '代表').join() : '受注 太郎',
        },
        'counterparty': {'name': long ? List.filled(20, '株式会社発注').join() : '株式会社発注'},
        if (long) 'notes': List.filled(60, '備考条件確認済み。').join(),
        'company_seal_enabled': true,
        'company_seal_snapshot': {'version': 1, 'style': 'legacy', 'name': '株式会社受注'},
      },
    });

  test('renders saved acceptance with square seal, including long registered parties', () async {
    final font = await CompanySealPdf.loadFont();
    for (final long in [false, true]) {
      final document = pw.Document(theme: pw.ThemeData.withFont(base: font, bold: font));
      await InvoiceOrderAcceptancePdf.append(document, attachment(long: long),
        regularFont: font, boldFont: font);
      final bytes = await document.save();
      expect(bytes.length, greaterThan(1000));
      final directory = Platform.environment['SKO_PDF_OUTPUT_DIR'];
      if (directory != null) {
        Directory(directory).createSync(recursive: true);
        File('$directory/invoice-order-acceptance${long ? '-long' : ''}.pdf').writeAsBytesSync(bytes);
      }
    }
  });

  test('unified invoice builder appends acceptance without changing invoice totals', () async {
    final font = await CompanySealPdf.loadFont();
    final invoice = InvoiceEngine.calculate(customerId: '株式会社発注',
      invoiceId: 'fixture-invoice', billingPeriod: '2026年10月',
      detailMode: InvoiceDetailMode.consolidatedOnly,
      sites: const [SiteInvoiceCalculation(siteId: 'site', siteName: '補修工事',
        lines: [InvoiceLine(label: '工事', quantity: 1, unitPriceYen: 100000)])],
      taxRateBps: 1000);
    const settings = InvoiceSettingsData(companyName: '株式会社受注', taxRate: 10,
      welfareRate: 0, templateTitle: '請求書', footerNote: '', bankName: '',
      bankBranch: '', bankAccountType: '', bankAccountNumber: '', bankAccountHolder: '',
      companySealEnabled: false);
    final bytes = await InvoicePdfService.buildPdf([invoice], settings: settings,
      regularFont: font, boldFont: font,
      approvalsByInvoice: const {'fixture-invoice': []},
      acceptanceByInvoice: {'fixture-invoice': attachment()});
    expect(invoice.grandTotalYen, 110000);
    final directory = Platform.environment['SKO_PDF_OUTPUT_DIR'];
    if (directory != null) {
      Directory(directory).createSync(recursive: true);
      File('$directory/invoice-with-acceptance.pdf').writeAsBytesSync(bytes);
    }
  });

  test('rejects invalid calendar date rather than normalizing it', () async {
    final font = await CompanySealPdf.loadFont();
    await expectLater(InvoiceOrderAcceptancePdf.append(pw.Document(),
      attachment(date: '2026-02-30'), regularFont: font, boldFont: font),
      throwsStateError);
  });
}

