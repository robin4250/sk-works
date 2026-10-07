import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/domain/invoice_engine.dart';
import 'package:sk_works/features/invoices/invoice_approval_repository.dart';
import 'package:sk_works/features/invoices/invoice_pdf_service.dart';
import 'package:sk_works/features/invoices/invoice_settings_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fontPath = Platform.environment['SKO_PDF_FONT_PATH'];
  final skipReason = fontPath == null
      ? 'Set SKO_PDF_FONT_PATH to an embedded Japanese TTF.'
      : false;
  late pw.Font font;
  late Directory output;
  late bool temporaryOutput;
  final invoice = InvoiceCalculationResult(
    invoiceId: 'personal-stamp-fixture',
    customerId: '株式会社 山田建設',
    billingPeriod: '2026年10月',
    detailMode: InvoiceDetailMode.siteBreakdownOnInvoice,
    invoiceNumber: '202610-001',
    issueDate: DateTime(2026, 10, 31),
    periodStart: DateTime(2026, 10, 1),
    periodEnd: DateTime(2026, 10, 31),
    siteCalculations: [],
    taxRateBps: 1000,
    subtotalYenOverride: 1100000,
    taxYenOverride: 110000,
    grandTotalYenOverride: 1210000,
  );
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
    bankAccountHolder: 'カ）スミダケンセツ',
  );
  setUpAll(() {
    if (fontPath == null) return;
    font = pw.Font.ttf(ByteData.sublistView(File(fontPath).readAsBytesSync()));
    final configured = Platform.environment['SKO_PDF_OUTPUT_DIR'];
    temporaryOutput = configured == null;
    output = configured == null
        ? Directory.systemTemp.createTempSync('sko-personal-stamp-')
        : Directory(configured);
    output.createSync(recursive: true);
  });
  tearDownAll(() {
    if (fontPath != null && temporaryOutput) output.deleteSync(recursive: true);
  });

  InvoiceApprovalRecord approval(
    int position,
    String name, {
    String status = 'approved',
    String role = 'approval',
    String mode = 'actual',
    DateTime? actual,
    DateTime? override,
  }) => InvoiceApprovalRecord(
    userId: 'user-$position',
    name: name,
    position: position,
    status: status,
    canCurrentUserApprove: false,
    approvedAt: actual,
    displayDateOverride: override,
    displayDateMode: mode,
    stampRole: role,
  );

  Future<Map<String, dynamic>> inspect(
    String filename,
    List<InvoiceApprovalRecord> approvals,
  ) async {
    final bytes = await InvoicePdfService.buildPdf(
      [invoice],
      settings: settings,
      regularFont: font,
      boldFont: font,
      approvalsByInvoice: {invoice.invoiceId: approvals},
    );
    final file = File('${output.path}/$filename')..writeAsBytesSync(bytes);
    final result = await Process.run('python', [
      '-c',
      r'''
import fitz,json,sys
pdf=fitz.open(sys.argv[1]); p=pdf[0]
cells=[]
for i in range(3):
 x=384.2756+i*176/3
 clip=fitz.Rect(x,773,x+176/3,807)
 spans=[s for b in p.get_text('dict',clip=clip)['blocks'] if b['type']==0 for l in b['lines'] for s in l['spans']]
 cells.append({'text':''.join(s['text'] for s in spans),'colors':[s['color'] for s in spans]})
print(json.dumps({'pages':len(pdf),'width':p.rect.width,'height':p.rect.height,'text':p.get_text(),'cells':cells},ensure_ascii=False))
''',
      file.path,
    ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    return jsonDecode(result.stdout.toString()) as Map<String, dynamic>;
  }

  test('actual invoice PDF shows roles and independent display dates only for approved people', () async {
    final actual = DateTime.utc(2026, 10, 7, 23);
    final report = await inspect('invoice_approved_stamps.pdf', [
      approval(
        1,
        '斉藤　隆一',
        role: 'confirmation',
        actual: actual,
        override: DateTime(2026, 9, 30),
      ),
      approval(2, '山田　太郎', mode: 'none', actual: actual),
      approval(3, '鈴木　一郎', actual: actual),
    ]);
    expect(report['pages'], 1);
    expect(report['width'], closeTo(595.2756, .01));
    expect(report['height'], closeTo(841.8898, .01));
    final cells = (report['cells'] as List).cast<Map<String, dynamic>>();
    expect(cells[0]['text'], contains('確認'));
    expect(cells[0]['text'], contains('斉藤'));
    expect(cells[0]['text'], contains('2026.09.30'));
    expect(cells[1]['text'], contains('承認'));
    expect(cells[1]['text'], contains('山田'));
    expect(cells[1]['text'], isNot(contains(RegExp(r'\d{4}\.\d{2}\.\d{2}'))));
    expect(cells[2]['text'], contains('承認'));
    expect(cells[2]['text'], contains('鈴木'));
    expect(cells[2]['text'], contains('2026.10.08'));
    for (final cell in cells) {
      expect(cell['colors'], contains(0xD9272E));
    }
    for (final amount in ['1,100,000', '110,000', '1,210,000']) {
      expect(report['text'], contains(amount));
    }
  }, skip: skipReason);

  test('pending approvals leave all adopted stamp cells empty', () async {
    final report = await inspect('invoice_pending_stamps.pdf', [
      for (var i = 1; i <= 3; i++)
        approval(
          i,
          '未承認　担当$i',
          status: 'pending',
          actual: DateTime.utc(2026, 10, 8),
          override: DateTime(2026, 9, 30),
        ),
    ]);
    for (final cell in report['cells'] as List) {
      expect((cell as Map)['text'], isEmpty);
      expect(cell['colors'], isEmpty);
    }
    expect(report['text'], isNot(contains('未承認')));
    expect(report['text'], contains('1,210,000'));
  }, skip: skipReason);

  test(
    'approved record without actual date never invents a rendered date',
    () async {
      final report = await inspect('invoice_missing_stamp_date.pdf', [
        approval(1, '佐藤　次郎'),
      ]);
      final cells = report['cells'] as List;
      expect((cells[0] as Map)['text'], contains('佐藤'));
      expect(
        (cells[0] as Map)['text'],
        isNot(contains(RegExp(r'\d{4}\.\d{2}\.\d{2}'))),
      );
      expect((cells[1] as Map)['text'], isEmpty);
      expect((cells[2] as Map)['text'], isEmpty);
    },
    skip: skipReason,
  );
}
