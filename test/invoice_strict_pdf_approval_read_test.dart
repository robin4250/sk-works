import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/data/supabase_backend.dart';
import 'package:sk_works/domain/company_seal_snapshot.dart';
import 'package:sk_works/domain/invoice_engine.dart';
import 'package:sk_works/features/invoices/invoice_approval_repository.dart';
import 'package:sk_works/features/invoices/invoice_pdf_service.dart';
import 'package:sk_works/features/invoices/invoice_settings_repository.dart';
import 'package:sk_works/features/shared/company_seal_pdf.dart';

const _id = '11111111-1111-4111-8111-111111111111';
const _settings = InvoiceSettingsData(
  companyName: '現在の別会社名',
  taxRate: 10,
  welfareRate: 0,
  templateTitle: '請求書',
  footerNote: '',
  bankName: '',
  bankBranch: '',
  bankAccountType: '',
  bankAccountNumber: '',
  bankAccountHolder: '',
);
InvoiceCalculationResult _invoice() => InvoiceCalculationResult(
  invoiceId: _id,
  customerId: '保存済み取引先',
  billingPeriod: '2025年8月',
  detailMode: InvoiceDetailMode.consolidatedOnly,
  siteCalculations: const [],
  taxRateBps: 1000,
  subtotalYenOverride: 12000,
  taxYenOverride: 1200,
  grandTotalYenOverride: 13200,
  companySealSnapshot: CompanySealSnapshot.fromJson({
    'version': 1,
    'style': 'legacy',
    'name': '保存済み会社',
  }),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final fixtures in <Map<String, List<InvoiceApprovalRecord>>?>[
    null,
    {'another-invoice': const []},
  ]) {
    test(
      'strict PDF rejects unavailable approvals unless exact fixture key was provided: $fixtures',
      () async {
        expect(SupabaseBackend.isInitialized, false);
        final invoice = _invoice();
        await expectLater(
          InvoicePdfService.buildPdf(
            [invoice],
            settings: _settings,
            approvalsByInvoice: fixtures,
            allowLegacyApprovalInitialization: false,
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'unverified approval error',
              '承認情報を確認できません。請求書を再読み込みしてください。',
            ),
          ),
        );
        // Approval availability fails before any font fetch or PDF generation.
        expect(invoice.grandTotalYen, 13200);
        expect(invoice.companySealSnapshot.name, '保存済み会社');
      },
    );
  }

  test(
    'strict PDF accepts explicit exact approval fixture and preserves saved seal and amounts',
    () async {
      expect(SupabaseBackend.isInitialized, false);
      final invoice = _invoice();
      final seal = invoice.companySealSnapshot;
      final regular = await CompanySealPdf.loadFont();
      final bold = await CompanySealPdf.loadFont();
      final bytes = await InvoicePdfService.buildPdf(
        [invoice],
        settings: _settings,
        regularFont: regular,
        boldFont: bold,
        approvalsByInvoice: const {_id: <InvoiceApprovalRecord>[]},
        allowLegacyApprovalInitialization: false,
      );
      expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
      final temporary = Directory.systemTemp.createTempSync(
        'sko-strict-invoice-',
      );
      addTearDown(() => temporary.deleteSync(recursive: true));
      final file = File('${temporary.path}/saved-invoice.pdf')
        ..writeAsBytesSync(bytes);
      final inspected = await Process.run('python', [
        '-c',
        r'''
import fitz,json,sys
with fitz.open(sys.argv[1]) as pdf:
 print(json.dumps({'pages':len(pdf),'text':'\n'.join(p.get_text() for p in pdf),'red_shapes':sum(1 for p in pdf for d in p.get_drawings() if d['color'] and d['color'][0]>.9 and d['color'][1]<.1 and d['color'][2]<.1)},ensure_ascii=False))
''',
        file.path,
      ]);
      expect(inspected.exitCode, 0, reason: inspected.stderr.toString());
      final report =
          jsonDecode(inspected.stdout.toString()) as Map<String, dynamic>;
      expect(report['pages'], 1);
      expect(report['text'], contains('保存済み会社'));
      expect(report['text'], isNot(contains('現在の別会社名')));
      expect(report['text'], contains('13,200'));
      expect(report['red_shapes'], greaterThan(0));
      expect(identical(invoice.companySealSnapshot, seal), true);
      expect(invoice.grandTotalYen, 13200);
    },
    skip: Platform.environment['SKO_PDF_FONT_PATH'] == null
        ? 'Native PDF inspection requires the dedicated SKO_PDF_FONT_PATH/PyMuPDF environment; strict unavailable-approval tests always run.'
        : false,
  );
}
