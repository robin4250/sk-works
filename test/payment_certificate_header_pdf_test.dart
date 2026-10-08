import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/features/payroll/payment_certificate_pdf_service.dart';
import 'package:sk_works/features/payroll/payment_certificate_repository.dart';
import 'package:sk_works/features/shared/company_seal_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fontPath = Platform.environment['SKO_PDF_FONT_PATH'];

  test('short seal columns preserve right-to-left reading order', () {
    expect(CompanySealPdf.verticalColumns('親会社'), ['親', '会', '社']);
  });

  test('company label and seal occupy separate actual PDF areas', () async {
    final configured = Platform.environment['SKO_PDF_OUTPUT_DIR'];
    final output = configured == null
        ? Directory.systemTemp.createTempSync('sko-certificate-header-')
        : Directory(configured);
    output.createSync(recursive: true);
    final font = pw.Font.ttf(ByteData.sublistView(
      await File(fontPath!).readAsBytes(),
    ));
    try {
      const names = ['親会社', '株式会社首都圏建設設備保守管理および共同現場工事支援'];
      for (var i = 0; i < 4; i++) {
        final name = names[i ~/ 2];
        final enabled = i.isEven;
        final record = PaymentCertificateRecord(
          id: 'header-$i', partnerCompanyName: '検証用下請会社',
          payerCompanyName: name, payerCompanySealEnabled: enabled,
          payerPostalCode: '160-0022',
          payerAddress: '東京都新宿区新宿1-2-3（検証用）',
          payerPhone: '03-0000-0011', payerFax: '03-0000-0012',
          periodStart: DateTime(2026, 10), periodEnd: DateTime(2026, 10, 31),
          grossAmount: 20000, deductions: 0, netAmount: 20000,
          status: 'draft', revision: 1,
          lines: const [PaymentCertificateLine(
            siteName: '共同工事現場', workContent: '請け負い（税別）',
            quantityLabel: '一式', unitPriceYen: 20000, amountYen: 20000,
          )],
        );
        final bytes = await PaymentCertificatePdfService.buildPdf(
          record, regularFont: font, boldFont: font,
        );
        final stem = '${output.path}/payment_agreement_header_${i + 1}';
        File('$stem.pdf').writeAsBytesSync(bytes);
        final checked = await Process.run('python', [
          '-c',
          '''import fitz,json,sys
d=fitz.open(sys.argv[1]); p=d[0]
p.get_pixmap(matrix=fitz.Matrix(2,2),alpha=False).save(sys.argv[2])
spans=[s for b in p.get_text('dict')['blocks'] if 'lines' in b for l in b['lines'] for s in l['spans']]
red=[s for s in spans if s['color']==0xff0000]
black=[s for s in spans if s['color']==0 and s['bbox'][0]>300 and s['bbox'][1]>90]
for s in black:
 for seal in red:
  assert not fitz.Rect(s['bbox']).intersects(fitz.Rect(seal['bbox'])), (s,seal)
print(json.dumps({'text':p.get_text(),'red_count':len(red)},ensure_ascii=False))''',
          '$stem.pdf', '$stem.png',
        ]);
        expect(checked.exitCode, 0, reason: checked.stderr.toString());
        final report = jsonDecode(checked.stdout.toString()) as Map;
        final text = (report['text'] as String).replaceAll(RegExp(r'\s+'), '');
        expect(text, contains(name));
        expect(text, contains(record.payerAddress));
        expect(text, contains(record.payerPhone));
        expect(text, contains(record.payerFax));
        expect((report['red_count'] as num) > 0, enabled);
      }
    } finally {
      if (configured == null) output.deleteSync(recursive: true);
    }
  }, skip: fontPath == null ? 'Actual PDF header fixtures require the CI font.' : false);
}
