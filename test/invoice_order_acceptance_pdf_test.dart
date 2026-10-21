import 'dart:io';

import 'package:sk_works/domain/company_seal_snapshot.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/features/invoices/invoice_order_acceptance_pdf.dart';
import 'package:sk_works/features/invoices/invoice_acceptance_resolver.dart';
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
    final defaults = Map<String, dynamic>.from(attachment().payload)
      ..remove('order_date')..remove('issue_date');
    final automatic = InvoiceAcceptanceResolver.resolve({
      'attachment': null, 'source_locked': false, 'source_blocked': false,
      'source_changed': false, 'defaults': defaults,
      'template': {'acceptance_text': '{order_date}付の注文書を承諾します。'},
    }, issueDate: DateTime(2026, 10, 16))!;
    final automaticBytes = await InvoicePdfService.buildPdf([invoice], settings: settings,
      regularFont: font, boldFont: font,
      approvalsByInvoice: const {'fixture-invoice': []},
      acceptanceByInvoice: {'fixture-invoice': automatic});
    expect(invoice.grandTotalYen, 110000);
    final directory = Platform.environment['SKO_PDF_OUTPUT_DIR'];
    if (directory != null) {
      Directory(directory).createSync(recursive: true);
      File('$directory/invoice-with-acceptance.pdf').writeAsBytesSync(bytes);
      File('$directory/invoice-with-automatic-acceptance.pdf').writeAsBytesSync(automaticBytes);
    }
  });

  test('automatic output includes locked invoices without changing page one or saved originals', () async {
    final font = await CompanySealPdf.loadFont();
    final parentSeal = CompanySealSnapshot.fromJson({
      'version': 1, 'style': 'legacy', 'name': '株式会社受注',
    });
    final invoice = InvoiceEngine.calculate(customerId: '株式会社発注',
      invoiceId: 'automatic-fixture', billingPeriod: '2026年10月',
      issueDate: DateTime(2026, 10, 16), companySealSnapshot: parentSeal,
      detailMode: InvoiceDetailMode.consolidatedOnly,
      sites: const [SiteInvoiceCalculation(siteId: 'site', siteName: '補修工事',
        lines: [InvoiceLine(label: '工事', quantity: 1, unitPriceYen: 100000)])],
      taxRateBps: 1000);
    const settings = InvoiceSettingsData(companyName: '株式会社受注', taxRate: 10,
      welfareRate: 0, templateTitle: '請求書', footerNote: '', bankName: '',
      bankBranch: '', bankAccountType: '', bankAccountNumber: '', bankAccountHolder: '',
      companySealEnabled: true);
    Future<List<int>> render(TradeDocumentAttachment? value) => InvoicePdfService.buildPdf(
      [invoice], settings: settings, regularFont: font, boldFont: font,
      approvalsByInvoice: const {'automatic-fixture': []},
      acceptanceByInvoice: {'automatic-fixture': value});
    final baseline = await render(null);
    final outputs = <String, List<int>>{'invoice-base': baseline};
    for (final locked in [false, true]) {
      final defaults = Map<String, dynamic>.from(attachment().payload)
        ..remove('order_date')..remove('issue_date');
      defaults['company_seal_snapshot'] = {
        'version': 1, 'style': 'legacy', 'name': '後から変更した現在印',
      };
      final workspace = <String, dynamic>{
        'source_locked': locked, 'source_blocked': false, 'source_changed': false,
        'attachment': null, 'auto_generate': true, 'defaults': defaults,
        'template': {'acceptance_text': '{order_date}付の注文書を承諾します。'},
      };
      final value = InvoiceAcceptanceResolver.resolve(workspace, issueDate: invoice.issueDate,
        parentSealSnapshot: invoice.companySealSnapshot,
        parentSealEnabled: settings.companySealEnabled)!;
      expect(value.payload['company_seal_snapshot'], {
        'version': 1, 'style': 'legacy', 'name': '株式会社受注',
      });
      expect(workspace['attachment'], isNull);
      outputs[locked ? 'invoice-locked-auto' : 'invoice-unlocked-auto'] = await render(value);
      if (locked) {
        workspace['auto_generate'] = false;
        final disabled = InvoiceAcceptanceResolver.resolve(workspace, issueDate: invoice.issueDate,
          parentSealSnapshot: invoice.companySealSnapshot,
          parentSealEnabled: settings.companySealEnabled);
        expect(disabled, isNull);
        outputs['invoice-locked-off'] = await render(disabled);
        final saved = attachment(date: '2026-10-20');
        workspace['attachment'] = {'version': 7, 'payload': saved.payload};
        final original = InvoiceAcceptanceResolver.resolve(workspace, issueDate: invoice.issueDate,
          parentSealSnapshot: CompanySealSnapshot.legacy, parentSealEnabled: false)!;
        expect(original.version, 7);
        expect(original.payload, saved.payload);
        outputs['invoice-locked-saved'] = await render(original);
      }
    }
    expect(invoice.companySealSnapshot, same(parentSeal));
    expect(invoice.grandTotalYen, 110000);
    for (final bytes in outputs.values) { expect(bytes.length, greaterThan(1000)); }
    final directory = Platform.environment['SKO_AUTOMATIC_PDF_OUTPUT_DIR'];
    if (directory != null) {
      Directory(directory).createSync(recursive: true);
      for (final entry in outputs.entries) {
        File('$directory/${entry.key}.pdf').writeAsBytesSync(entry.value);
      }
    }
  });

  test('rejects invalid calendar date rather than normalizing it', () async {
    final font = await CompanySealPdf.loadFont();
    await expectLater(InvoiceOrderAcceptancePdf.append(pw.Document(),
      attachment(date: '2026-02-30'), regularFont: font, boldFont: font),
      throwsStateError);
  });
}


