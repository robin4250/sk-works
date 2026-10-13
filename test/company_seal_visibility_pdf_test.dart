import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/domain/invoice_engine.dart';
import 'package:sk_works/features/invoices/invoice_pdf_service.dart';
import 'package:sk_works/features/invoices/invoice_approval_repository.dart';
import 'package:sk_works/features/invoices/invoice_settings_repository.dart';
import 'package:sk_works/features/payroll/payment_certificate_pdf_service.dart';
import 'package:sk_works/features/payroll/payment_certificate_repository.dart';
import 'package:sk_works/features/payroll/payroll_pdf_service.dart';
import 'package:sk_works/features/payroll/payroll_statement_repository.dart';

InvoiceSettingsData settings(bool enabled) => InvoiceSettingsData(
  companyName: '株式会社青空工業',
  companySealEnabled: enabled,
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fontPath = Platform.environment['SKO_PDF_FONT_PATH'];

  test('attendance-free certificate preview inherits company seal visibility', () {
    const setting = PartnerPaymentSetting(
      partnerCompanyId: 'partner', partnerCompanyName: '取引先',
      dailyRateYen: 0, overtimeHourRateYen: 0,
      earlyHourRateYen: 0, nightHourRateYen: 0,
    );
    for (final enabled in [true, false]) {
      final preview = PaymentCertificateRepository.emptyPreview(
        setting,
        company: {'name': '株式会社青空工業', 'company_seal_enabled': enabled},
        month: DateTime(2026, 10),
      );
      expect(preview.payerCompanySealEnabled, enabled);
      expect(preview.netAmount, 0);
    }
    final legacy = PaymentCertificateRepository.emptyPreview(
      setting, company: const {'name': '株式会社青空工業'},
      month: DateTime(2026, 10),
    );
    expect(legacy.payerCompanySealEnabled, isTrue);
  });

  test('three PDFs hide only company seal and preserve company text geometry', () async {
    final configured = Platform.environment['SKO_PDF_OUTPUT_DIR'];
    final output = configured == null
        ? Directory.systemTemp.createTempSync('sko-seal-visibility-')
        : Directory(configured);
    output.createSync(recursive: true);
    final fontData = ByteData.sublistView(File(fontPath!).readAsBytesSync());
    try {
      for (final enabled in [true, false]) {
        pw.Font font() => pw.Font.ttf(fontData);
        final start = DateTime(2026, 10, 1);
        final end = DateTime(2026, 10, 31);
        final invoice = InvoiceCalculationResult(
          customerId: '取引先', billingPeriod: '2026年10月',
          detailMode: InvoiceDetailMode.siteBreakdownOnInvoice,
          siteCalculations: const [], taxRateBps: 1000,
          subtotalYenOverride: 10000, taxYenOverride: 1000,
          grandTotalYenOverride: 11000,
        );
        final payroll = PayrollStatementRecord(
          id: 'visibility', companyName: '株式会社青空工業', workerName: '確認社員',
          periodStart: start, periodEnd: end,
          grossPay: 10000, deductions: 1000, netPay: 9000,
          detail: {
            'company_seal_enabled': enabled, '基本給': 10000,
            'payroll_confirmations': [
              {'name': '確認担当', 'confirmed_at': '2026-10-31T01:00:00Z'},
            ],
          },
        );
        final certificate = PaymentCertificateRecord(
          id: 'visibility', partnerCompanyName: '取引先',
          periodStart: start, periodEnd: end,
          grossAmount: 10000, deductions: 1000, netAmount: 9000,
          status: 'approved', revision: 1,
          payerCompanyName: '株式会社青空工業',
          payerCompanySealEnabled: enabled,
          payerPhone: '03-1234-5678',
        );
        Future<Uint8List> generate(
          String report,
          Future<Uint8List> Function() build,
        ) async {
          try {
            return await build();
          } catch (error, stack) {
            Error.throwWithStackTrace(
              TestFailure('$report company seal ${enabled ? 'ON' : 'OFF'}: $error'),
              stack,
            );
          }
        }
        final files = {
          'invoice': await generate('invoice', () => InvoicePdfService.buildPdf(
            [invoice], settings: settings(enabled),
            approvalsByInvoice: const {
              '': [InvoiceApprovalRecord(
                userId: 'reviewer', name: '確認担当', position: 1,
                status: 'approved', canCurrentUserApprove: false,
                displayDateMode: 'none',
              )],
            },
            regularFont: font(), boldFont: font(),
          )),
          'payroll': await generate('payroll', () => PayrollPdfService.buildPdf(
            payroll, regularFont: font(), boldFont: font(),
          )),
          'certificate': await generate('certificate', () => PaymentCertificatePdfService.buildPdf(
            certificate, regularFont: font(), boldFont: font(),
          )),
        };
        for (final entry in files.entries) {
          File('${output.path}/company_seal_${entry.key}_${enabled ? 'on' : 'off'}.pdf')
              .writeAsBytesSync(entry.value);
        }
      }
      final result = await Process.run('python', ['-c', r'''
import fitz,json,sys
from pathlib import Path
out={}
for kind in ['invoice','payroll','certificate']:
    pair={}
    for enabled in ['on','off']:
        doc=fitz.open(Path(sys.argv[1])/f'company_seal_{kind}_{enabled}.pdf')
        page=doc[0]
        spans=[s for b in page.get_text('dict')['blocks'] for l in b.get('lines',[]) for s in l['spans']]
        company=[s['bbox'] for s in spans if s['text']=='株式会社青空工業']
        seals=[d for d in page.get_drawings() if d['color'] and d['color'][0]>.9 and d['color'][1]<.1 and d['color'][2]<.1 and d['rect'].width>=30 and d['rect'].height>=30]
        personal=[d for d in page.get_drawings() if d['color'] and d['color'][0]>.7 and d['color'][1]<.2 and d['color'][2]<.2 and 10<d['rect'].width<30 and 10<d['rect'].height<30]
        pair[enabled]={'personal_count':len(personal),'company':company,'seal_count':len(seals),'pages':len(doc),'size':[page.rect.width,page.rect.height],'text':page.get_text()}
    assert pair['on']['seal_count']>0,(kind,pair)
    assert pair['off']['seal_count']==0,(kind,pair)
    assert pair['on']['company']==pair['off']['company'],(kind,pair)
    assert pair['on']['company'],(kind,pair)
    if kind!='certificate':
        assert pair['off']['personal_count']>0,(kind,pair)
        assert pair['on']['personal_count']==pair['off']['personal_count'],(kind,pair)
    assert pair['on']['pages']==pair['off']['pages']==1
    assert pair['on']['size']==pair['off']['size']
    assert '9,000' in pair['off']['text'] if kind!='invoice' else '11,000' in pair['off']['text']
    out[kind]=pair
print(json.dumps(out,ensure_ascii=False))
''', output.path]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect((jsonDecode(result.stdout.toString()) as Map).length, 3);
    } finally {
      if (configured == null) output.deleteSync(recursive: true);
    }
  }, skip: fontPath == null ? 'Set SKO_PDF_FONT_PATH to an embedded Japanese TTF.' : false);
}
