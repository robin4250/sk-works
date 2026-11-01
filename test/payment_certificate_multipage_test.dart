import 'dart:convert';
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
  final fontPath = Platform.environment['SKO_PDF_FONT_PATH'];
  if (fontPath == null || Platform.environment['SKO_PDF_PYTHON'] == null) {
    test(
      'multipage financial PDFs retain all rows',
      () {},
      skip:
          'Opt in with SKO_PDF_FONT_PATH (Japanese TTF) and SKO_PDF_PYTHON (Python with pypdf).',
    );
    return;
  }
  final output =
      Platform.environment['SKO_PDF_OUTPUT_DIR'] ??
      Directory.systemTemp.createTempSync('sko-payment-pages-').path;
  Directory(output).createSync(recursive: true);
  final font = pw.Font.ttf(
    ByteData.sublistView(File(fontPath).readAsBytesSync()),
  );
  Future<void> inspect(String name, Uint8List bytes, String prefix) async {
    final path = '$output/$name.pdf';
    File(path).writeAsBytesSync(bytes);
    final result =
        await Process.run(Platform.environment['SKO_PDF_PYTHON'] ?? 'python3', [
          '-c',
          r'''
import json,re,sys
from pypdf import PdfReader
r=PdfReader(sys.argv[1]); prefix=sys.argv[2]; hits=[];outside=[]
for n,p in enumerate(r.pages):
 def visit(text,cm,tm,font,size):
  for item in re.findall(prefix+r'\d{3}',text):
   x=tm[4]*cm[0]+tm[5]*cm[2]+cm[4];y=tm[4]*cm[1]+tm[5]*cm[3]+cm[5]
   if not (0<=x<=float(p.mediabox.width) and 0<=y<=float(p.mediabox.height)):outside.append({'id':item,'page':n+1,'x':x,'y':y})
 p.extract_text(visitor_text=visit)
 hits+=re.findall(prefix+r'\d{3}',p.extract_text())
print(json.dumps({'pages':len(r.pages),'ids':hits,'outside_page':outside}))
''',
          path,
          prefix,
        ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final report = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    File('$output/$name-report.json').writeAsStringSync(jsonEncode(report));
    expect(report['ids'], [
      for (var i = 1; i <= 76; i++) '$prefix${i.toString().padLeft(3, '0')}',
    ]);
    expect(report['pages'], greaterThan(1));
    expect(report['outside_page'], isEmpty);
    if (prefix == 'PAY') {
      final check = await Process.run(
        Platform.environment['SKO_PDF_PYTHON'] ?? 'python3',
        [
          '-c',
          r'''
import sys,re
from pypdf import PdfReader
pages=[p.extract_text() for p in PdfReader(sys.argv[1]).pages]
for n,text in enumerate(pages,1):
 assert f'P.{n:03}/{len(pages):03}' in text,(n,text[:150])
 assert '作業所名' in re.sub(r'\s+','',text)
for term in ['小計','福利厚生費','消費税','¥76,000']:
 assert sum(p.count(term) for p in pages)==1,term
 assert term in pages[-1],term
''',
          path,
        ],
      );
      expect(check.exitCode, 0, reason: check.stderr.toString());
    }
  }

  test(
    'invoice preserves all 76 unique detail rows in visible page order',
    () async {
      final invoice = InvoiceCalculationResult(
        customerId: 'Synthetic Recipient',
        billingPeriod: '2026-11',
        detailMode: InvoiceDetailMode.siteBreakdownOnInvoice,
        siteCalculations: [
          SiteInvoiceCalculation(
            siteId: 'synthetic',
            siteName: 'Synthetic Site',
            lines: [
              for (var i = 1; i <= 76; i++)
                InvoiceLine(
                  label: 'INV${i.toString().padLeft(3, '0')}',
                  quantity: 1,
                  unitPriceYen: 1000,
                ),
            ],
          ),
        ],
        taxRateBps: 1000,
        invoiceNumber: 'SYNTHETIC',
        issueDate: DateTime(2026, 11, 1),
        periodStart: DateTime(2026, 11, 1),
        periodEnd: DateTime(2026, 11, 30),
      );
      const settings = InvoiceSettingsData(
        companyName: 'Synthetic Issuer',
        taxRate: 10,
        welfareRate: 0,
        templateTitle: 'Synthetic Invoice',
        footerNote: '',
        bankName: 'Synthetic Bank',
        bankBranch: 'Synthetic Branch',
        bankAccountType: '普通',
        bankAccountNumber: '0000000',
        bankAccountHolder: 'テスト',
        companySealEnabled: false,
      );
      await inspect(
        'invoice-76',
        await InvoicePdfService.buildPdf(
          [invoice],
          settings: settings,
          regularFont: font,
          boldFont: font,
        ),
        'INV',
      );
    },
  );
  test(
    'payment certificate preserves all 76 unique detail rows in visible page order',
    () async {
      final record = PaymentCertificateRecord(
        id: 'synthetic-preview',
        partnerCompanyName: 'Synthetic Recipient',
        periodStart: DateTime(2026, 11, 1),
        periodEnd: DateTime(2026, 11, 30),
        grossAmount: 76000,
        deductions: 0,
        netAmount: 76000,
        status: 'preview',
        revision: 1,
        payerCompanyName: 'Synthetic Issuer',
        payerCompanySealEnabled: false,
        lines: [
          for (var i = 1; i <= 76; i++)
            PaymentCertificateLine(
              siteName: 'PAY${i.toString().padLeft(3, '0')}',
              workContent: 'Synthetic Work',
              quantityLabel: '1',
              unitPriceYen: 1000,
              amountYen: 1000,
            ),
        ],
      );
      await inspect(
        'payment-76',
        await PaymentCertificatePdfService.buildPdf(
          record,
          regularFont: font,
          boldFont: font,
        ),
        'PAY',
      );
    },
  );
}
