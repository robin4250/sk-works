import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/domain/invoice_engine.dart';
import 'package:sk_works/features/invoices/invoice_pdf_service.dart';
import 'package:sk_works/features/invoices/invoice_settings_repository.dart';

// Opt-in integration test: embedded font and PyMuPDF are required. Regular CI
// runs the deterministic unit tests without downloading external fonts.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fontPath = Platform.environment['SKO_PDF_FONT_PATH'];
  final skipReason = fontPath == null
      ? 'Set SKO_PDF_FONT_PATH to an embedded Japanese TTF.'
      : false;
  const settings = InvoiceSettingsData(
    companyName: 'すみだ建設株式会社',
    taxRate: 10,
    welfareRate: 0,
    templateTitle: '請求書',
    footerNote: '',
    bankName: 'SKO銀行',
    bankBranch: '東京支店',
    bankAccountType: '普通',
    bankAccountNumber: '1234567',
    bankAccountHolder: 'カ）スカダケンセツ',
    companyPostalCode: '125-0061',
    companyAddress: '東京都葛飾区亀有3丁目12番5号',
    companyPhone: '03-3601-1234',
    companyFax: '03-3601-5678',
    invoiceSubject: '10月分 工事請負代金',
    paymentDueText: '2026年11月25日',
  );
  late pw.Font font;
  late Directory output;
  late bool temporaryOutput;
  setUpAll(() {
    if (fontPath == null) return;
    font = pw.Font.ttf(ByteData.sublistView(File(fontPath).readAsBytesSync()));
    final configured = Platform.environment['SKO_PDF_OUTPUT_DIR'];
    temporaryOutput = configured == null;
    output =
        configured == null
              ? Directory.systemTemp.createTempSync('sko-invoice-pdf-')
              : Directory(configured)
          ..createSync(recursive: true);
  });
  tearDownAll(() {
    if (fontPath != null && temporaryOutput) output.deleteSync(recursive: true);
  });

  Future<Map<String, dynamic>> inspect(
    String name,
    InvoiceCalculationResult invoice, {
    InvoiceSettingsData? documentSettings,
  }) async {
    final bytes = await InvoicePdfService.buildPdf(
      [invoice],
      settings: documentSettings ?? settings,
      regularFont: font,
      boldFont: font,
    );
    final file = File('${output.path}/$name')..writeAsBytesSync(bytes);
    final result = await Process.run('python', [
      '-c',
      r'''
import fitz,json,sys
pdf=fitz.open(sys.argv[1])
print(json.dumps({'pages':[{'width':p.rect.width,'height':p.rect.height,'text':p.get_text(),'company_name_spans':[s['bbox'] for b in p.get_text('dict')['blocks'] for l in b.get('lines',[]) for s in l['spans'] if s['color']==0 and 740<s['bbox'][1]<780], 'seal_lefts':[d['rect'].x0 for d in p.get_drawings() if d['color'] and d['color'][0]>.9 and d['color'][1]<.1 and d['color'][2]<.1 and d['rect'].width>35], 'recipient_spans':[{ 'text':s['text'],'bbox':s['bbox']} for b in p.get_text('dict')['blocks'] for l in b.get('lines',[]) for s in l['spans'] if s['bbox'][0]<300 and 100<s['bbox'][1]<180], 'site_spans':[{ 'text':s['text'],'bbox':s['bbox']} for b in p.get_text('dict')['blocks'] for l in b.get('lines',[]) for s in l['spans'] if 62<=s['bbox'][0]<178 and 262<s['bbox'][1]<674], 'unit_price_spans':[{ 'text':s['text'],'bbox':s['bbox']} for b in p.get_text('dict')['blocks'] for l in b.get('lines',[]) for s in l['spans'] if 419<s['bbox'][0]<487 and 262<s['bbox'][1]<674], 'paper_rgba':list(p.get_pixmap(alpha=True).samples[:4]), 'horizontal_lines':[round(d['rect'].y0,2) for d in p.get_drawings() if abs(d['rect'].height)<.4 and d['rect'].width>530]} for p in pdf]},ensure_ascii=False))
''',
      file.path,
    ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    return jsonDecode(result.stdout.toString()) as Map<String, dynamic>;
  }

  InvoiceCalculationResult invoice(
    List<SiteInvoiceCalculation> sites, {
    bool sampleTotals = false,
    String customerPhone = '',
  }) => InvoiceCalculationResult(
    customerId: '株式会社 山田建設',
    customerPostalCode: '100-0001',
    customerPhone: customerPhone,
    customerAddress: '東京都千代田区丸の内1丁目1-1\n丸の内ビルディング10F',
    billingPeriod: '2026年10月',
    detailMode: InvoiceDetailMode.siteBreakdownOnInvoice,
    siteCalculations: sites,
    taxRateBps: 1000,
    invoiceNumber: '202610-001',
    issueDate: DateTime(2026, 10, 25),
    periodStart: DateTime(2026, 10, 1),
    periodEnd: DateTime(2026, 10, 31),
    subtotalYenOverride: sampleTotals ? 1100000 : null,
    taxYenOverride: sampleTotals ? 110000 : null,
    grandTotalYenOverride: sampleTotals ? 1210000 : null,
  );
  test(
    'adopted invoice fixture is A4 with 35 fixed rows and exact sample totals',
    () async {
      final report = await inspect(
        'generated_invoice_v8.pdf',
        invoice([], sampleTotals: true),
      );
      final pages = report['pages'] as List<dynamic>;
      expect(pages, hasLength(1));
      final page = pages.single as Map<String, dynamic>;
      expect(page['width'], closeTo(595.2756, .01));
      expect(page['height'], closeTo(841.8898, .01));
      final text = page['text'] as String;
      for (final label in [
        '100-0001',
        '東京都千代田区丸の内1丁目1-1',
        '現場名',
        '工事内容・摘要',
        '期間',
        '人数',
        'SKO銀行',
        '1234567',
        'すみだ建設株式会社',
        '1,100,000',
        '110,000',
        '1,210,000',
      ]) {
        expect(text, contains(label));
      }
      final lines = (page['horizontal_lines'] as List<dynamic>).cast<num>();
      for (var row = 1; row <= 35; row++) {
        expect(
          lines.any(
            (y) => (y - (262 + row * (669.8898 - 262) / 35)).abs() < .35,
          ),
          isTrue,
          reason: 'Missing fixed grid row $row',
        );
      }
    },
    skip: skipReason,
  );
  test('36 live detail rows paginate without losing line data', () async {
    final sites = [
      SiteInvoiceCalculation(
        siteId: 's',
        siteName: '新宿現場',
        lines: List.generate(
          36,
          (i) =>
              InvoiceLine(label: '工事${i + 1}', quantity: 1, unitPriceYen: 1000),
        ),
      ),
    ];
    final report = await inspect('invoice_pagination.pdf', invoice(sites));
    final pages = report['pages'] as List<dynamic>;
    expect(pages, hasLength(2));
    expect((pages[0] as Map)['text'], contains('工事35'));
    expect((pages[0] as Map)['text'], isNot(contains('工事36')));
    expect((pages[1] as Map)['text'], contains('工事36'));
    expect((pages[1] as Map)['text'], contains('39,600'));
  }, skip: skipReason);
  test(
    'welfare and adjustments reconcile displayed details with totals',
    () async {
      final report = await inspect(
        'invoice_welfare.pdf',
        invoice(const [
          SiteInvoiceCalculation(
            siteId: 's',
            siteName: '現場',
            welfareRateBps: 150,
            manualAdjustmentYen: -1000,
            lines: [
              InvoiceLine(label: '通常作業', quantity: 2, unitPriceYen: 25000),
            ],
          ),
        ]),
      );
      final text = ((report['pages'] as List).single as Map)['text'] as String;
      for (final value in [
        '通常作業',
        '福利厚生費（1.5%）',
        '値引き・調整',
        '735',
        '-1,000',
        '49,735',
        '4,974',
        '54,709',
      ]) {
        expect(text, contains(value));
      }
    },
    skip: skipReason,
  );
  test(
    'company seals follow different registered names with adopted overlap',
    () async {
      for (final companyName in ['山田建設', '株式会社北日本総合建設']) {
        final documentSettings = InvoiceSettingsData(
          companyName: companyName,
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
        final report = await inspect(
          'invoice_company_${companyName.runes.length}.pdf',
          invoice([]),
          documentSettings: documentSettings,
        );
        final page = (report['pages'] as List).single as Map;
        final companySpans = page['company_name_spans'] as List;
        expect(companySpans, hasLength(1));
        final rightEdge = (companySpans.single as List)[2] as num;
        final sealLefts = page['seal_lefts'] as List;
        expect(sealLefts, isNotEmpty);
        final sealLeft = sealLefts.cast<num>().reduce((a, b) => a < b ? a : b);
        expect(rightEdge - sealLeft, closeTo(11.8622, .05));
      }
    },
    skip: skipReason,
  );
  test('zero quantities and monetary values are blank without removing detail rows or frames', () async {
    final report = await inspect(
      'invoice_zero_amounts.pdf',
      invoice(const [
        SiteInvoiceCalculation(
          siteId: 'zero',
          siteName: '金額未設定現場',
          lines: [
            InvoiceLine(
              label: '通常作業',
              quantity: 0,
              unitPriceYen: 0,
              unitPriceText: '0',
            ),
          ],
        ),
      ]),
    );
    final page = (report['pages'] as List).single as Map;
    final text = page['text'] as String;
    expect(text, contains('金額未設定現場'));
    expect(text, contains('通常作業'));
    expect(text, contains('小計（税抜）'));
    expect(text, isNot(contains('¥0')));
    expect(RegExp(r'^0$', multiLine: true).hasMatch(text), isFalse);
    final lines = (page['horizontal_lines'] as List).cast<num>();
    for (var row = 1; row <= 35; row++) {
      expect(
        lines.any((y) => (y - (262 + row * (669.8898 - 262) / 35)).abs() < .35),
        isTrue,
      );
    }
  }, skip: skipReason);
  test('saved welfare rows display each site percentage once', () async {
    final report = await inspect(
      'invoice_welfare_rates.pdf',
      invoice(const [
        SiteInvoiceCalculation(
          siteId: 'a',
          siteName: 'A現場',
          welfareRateBps: 300,
          baseAmountYenOverride: 100000,
          welfareAmountYenOverride: 3000,
          subtotalYenOverride: 103000,
          lines: [
            InvoiceLine(label: '通常作業', quantity: 1, unitPriceYen: 100000),
            InvoiceLine(
              label: '（法定福利費）',
              quantity: 0,
              unitPriceYen: 0,
              amountYenOverride: 3000,
            ),
          ],
        ),
        SiteInvoiceCalculation(
          siteId: 'b',
          siteName: 'B現場',
          welfareRateBps: 150,
          baseAmountYenOverride: 100000,
          welfareAmountYenOverride: 1500,
          subtotalYenOverride: 101500,
          lines: [
            InvoiceLine(label: '通常作業', quantity: 1, unitPriceYen: 100000),
          ],
        ),
      ]),
    );
    final text = ((report['pages'] as List).single as Map)['text'] as String;
    expect('福利厚生費'.allMatches(text), hasLength(2));
    expect(text, contains('福利厚生費（3%）'));
    expect(text, contains('福利厚生費（1.5%）'));
    expect(text, contains('3,000'));
    expect(text, contains('1,500'));
    expect(text, contains('204,500'));
    expect(text, contains('20,450'));
    expect(text, contains('224,950'));
    final page = (report['pages'] as List).single as Map;
    final prices = (page['unit_price_spans'] as List)
        .map((span) => (span as Map)['text'])
        .toList();
    expect(prices, containsAll(['3%', '1.5%']));
    expect(page['paper_rgba'], [255, 255, 255, 255]);
  }, skip: skipReason);
  test(
    'registered customer contact details remain inside adopted recipient frame',
    () async {
      final report = await inspect(
        'invoice_customer_contact.pdf',
        invoice([], customerPhone: '03-1234-5678'),
      );
      final page = (report['pages'] as List).single as Map;
      final text = page['text'] as String;
      for (final label in [
        '株式会社 山田建設',
        '100-0001',
        '東京都千代田区丸の内1丁目1-1',
        '丸の内ビルディング10F',
        '03-1234-5678',
      ]) {
        expect(text.replaceAll(' ', ''), contains(label.replaceAll(' ', '')));
      }
      final phoneSpans = (page['recipient_spans'] as List).cast<Map>().where(
        (s) => (s['text'] as String).contains('03-1234-5678'),
      );
      expect(phoneSpans, hasLength(1));
      final bounds = (phoneSpans.single['bbox'] as List).cast<num>();
      expect(bounds[0], greaterThanOrEqualTo(28));
      expect(bounds[2], lessThanOrEqualTo(294));
      expect(bounds[1], greaterThanOrEqualTo(80));
      expect(bounds[3], lessThanOrEqualTo(176));
    },
    skip: skipReason,
  );
  test('site ditto mark is indented geometrically while names retain left alignment', () async {
    final report = await inspect(
      'invoice_ditto_indent.pdf',
      invoice(const [
        SiteInvoiceCalculation(
          siteId: 'ditto',
          siteName: '登録現場名',
          lines: [
            InvoiceLine(label: '通常作業', quantity: 1, unitPriceYen: 1000),
            InvoiceLine(label: '残業', quantity: 1, unitPriceYen: 500),
          ],
        ),
      ]),
    );
    final spans =
        (((report['pages'] as List).single as Map)['site_spans'] as List)
            .cast<Map>();
    final site = spans.singleWhere((s) => s['text'] == '登録現場名');
    final ditto = spans.singleWhere((s) => s['text'] == '〃');
    final siteX = (site['bbox'] as List)[0] as num;
    final dittoX = (ditto['bbox'] as List)[0] as num;
    expect(siteX, closeTo(65, .02));
    expect(dittoX - siteX, closeTo(5.5 * 5.4, .02));
    expect((ditto['bbox'] as List)[2] as num, lessThan(178));
  }, skip: skipReason);
}
