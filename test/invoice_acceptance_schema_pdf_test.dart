import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/domain/invoice_engine.dart';
import 'package:sk_works/features/invoices/invoice_acceptance_resolver.dart';
import 'package:sk_works/features/invoices/invoice_pdf_service.dart';
import 'package:sk_works/features/invoices/invoice_settings_repository.dart';
import 'package:sk_works/features/shared/company_seal_pdf.dart';
import 'trade_document_form_draft_test.dart' show formBody;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('authorized workspace schema selects fresh appendix; saved original wins', () async {
    final output = Platform.environment['INVOICE_SCHEMA_PDF_OUTPUT_DIR'];
    final defaults = formBody()..['kind'] = 'acceptance';
    defaults.remove('form_fields');
    defaults['issuer'] = {'name': '登録受注会社', 'address': '東京都',
      'representative_name': '登録代表者', 'phone': '03-1111-2222', 'fax': '03-3333-4444'};
    final workspace = <String, dynamic>{
      'source_locked': false, 'source_blocked': false, 'source_changed': false,
      'attachment': null, 'defaults': defaults, 'template': <String, dynamic>{},
    };
    final before = jsonEncode(workspace);
    final date = DateTime(2026, 10, 31);
    final old = InvoiceAcceptanceResolver.resolve(workspace, issueDate: date)!;
    expect(old.payload['form_fields']['schema'], 1);
    expect(jsonEncode(workspace), before);
    workspace['form_fields_schema_version'] = 2;
    final current = InvoiceAcceptanceResolver.resolve(workspace, issueDate: date)!;
    expect(current.payload['form_fields']['schema'], 2);
    expect(current.payload['form_fields']['progress_cutoff_day'], 'month_end');
    expect(current.payload['issuer']['fax'], '03-3333-4444');
    expect(current.payload['form_fields']['rows'][0]['unit_price_yen'], isNull);
    final historicalPayload = Map<String, dynamic>.from(old.payload)
      ..remove('contract_terms')..remove('form_fields');
    workspace['attachment'] = {'version': 7, 'payload': historicalPayload};
    final saved = InvoiceAcceptanceResolver.resolve(workspace, issueDate: date)!;
    expect(saved.version, 7);
    expect(saved.payload, historicalPayload);
    expect(saved.payload.containsKey('contract_terms'), isFalse);
    expect(saved.payload.containsKey('form_fields'), isFalse);
    final savedBefore = jsonEncode(saved.payload);
    const settings = InvoiceSettingsData(companyName: '登録受注会社', taxRate: 10,
      welfareRate: 0, templateTitle: '請求書', footerNote: '', bankName: '',
      bankBranch: '', bankAccountType: '', bankAccountNumber: '', bankAccountHolder: '',
      companySealEnabled: false);
    final invoice = InvoiceEngine.calculate(customerId: '登録取引会社', invoiceId: 'schema-fixture',
      billingPeriod: '2026年10月', detailMode: InvoiceDetailMode.consolidatedOnly,
      sites: [SiteInvoiceCalculation(siteId: 'site', siteName: '版選択の工事',
        lines: List.generate(36, (i) => InvoiceLine(label: '工事${i + 1}', quantity: 1, unitPriceYen: 1000)))], taxRateBps: 1000);
    final font = await CompanySealPdf.loadFont();
    for (final entry in {'missing-capability': old, 'current-capability': current, 'saved-original': saved}.entries) {
      final bytes = await InvoicePdfService.buildPdf([invoice], settings: settings,
        regularFont: font, boldFont: font, approvalsByInvoice: const {'schema-fixture': []},
        acceptanceByInvoice: {'schema-fixture': entry.value});
      expect(bytes.length, greaterThan(1000));
      if (output != null) {
        Directory(output).createSync(recursive: true);
        File('$output/${entry.key}.pdf').writeAsBytesSync(bytes);
      }
    }
    expect(jsonEncode(saved.payload), savedBefore);
    expect(invoice.grandTotalYen, 39600);
  });
}
