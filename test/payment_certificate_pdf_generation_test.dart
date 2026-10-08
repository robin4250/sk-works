import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/features/payroll/payment_certificate_pdf_service.dart';
import 'package:sk_works/features/payroll/payment_certificate_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fontPath = Platform.environment['SKO_PDF_FONT_PATH'];

  test(
    'zero certificate amounts remain blank without removing detail labels',
    () async {
      final font = pw.Font.ttf(
        ByteData.sublistView(await File(fontPath!).readAsBytes()),
      );
      final output = Directory.systemTemp.createTempSync(
        'sko-zero-certificate-',
      );
      try {
        final record = PaymentCertificateRecord(
          id: 'zero-certificate',
          partnerCompanyName: '取引先',
          periodStart: DateTime(2026, 10, 1),
          periodEnd: DateTime(2026, 10, 31),
          grossAmount: 0,
          deductions: 0,
          netAmount: 0,
          status: 'draft',
          revision: 1,
          payerCompanyName: '株式会社青空工業',
          lines: const [
            PaymentCertificateLine(
              siteName: '零額現場',
              workContent: '零額明細',
              quantityLabel: '1日',
              unitPriceYen: 0,
              amountYen: 0,
            ),
          ],
        );
        final bytes = await PaymentCertificatePdfService.buildPdf(
          record,
          regularFont: font,
          boldFont: font,
        );
        final file = File('${output.path}/zero.pdf')..writeAsBytesSync(bytes);
        final result = await Process.run('python', [
          '-c',
          'import fitz,sys; d=fitz.open(sys.argv[1]); '
              'assert len(d)==1; print(d[0].get_text())',
          file.path,
        ]);
        expect(result.exitCode, 0, reason: result.stderr.toString());
        final text = result.stdout.toString();
        expect(text, contains('零額現場'));
        expect(text, contains('零額明細'));
        expect(text, contains('合'));
        expect(text, contains('差'));
        expect(text, isNot(matches(RegExp(r'(^|\n)\s*[¥￥]?0(?:円)?\s*(\n|$)'))));
        expect(text, isNot(contains('¥')));
      } finally {
        output.deleteSync(recursive: true);
      }
    },
    skip: fontPath == null
        ? 'Set SKO_PDF_FONT_PATH to an embedded Japanese TTF.'
        : false,
  );

  test(
    'actual payment certificates preserve amounts and generate each payer seal',
    () async {
      final font = pw.Font.ttf(
        ByteData.sublistView(await File(fontPath!).readAsBytes()),
      );
      final configured = Platform.environment['SKO_PDF_OUTPUT_DIR'];
      final output = configured == null
          ? Directory.systemTemp.createTempSync('sko-payment-certificate-')
          : Directory(configured);
      output.createSync(recursive: true);
      try {
        final reports = <Map<String, dynamic>>[];
        final companies = ['すみだ建設株式会社', '株式会社青空工業'];
        for (var i = 0; i < companies.length; i++) {
          final record = PaymentCertificateRecord(
            id: 'certificate-fixture-$i',
            partnerCompanyName: '株式会社山田建設',
            periodStart: DateTime(2026, 10, 1),
            periodEnd: DateTime(2026, 10, 31),
            grossAmount: 525000,
            deductions: 25000,
            netAmount: 500000,
            status: 'confirmed',
            revision: 2,
            payerCompanyName: companies[i],
            payerPostalCode: '125-0061',
            payerAddress: '東京都葛飾区亀有3丁目1番2号',
            payerPhone: '03-3601-1234',
            payerFax: '03-3601-5678',
            lines: const [
              PaymentCertificateLine(
                siteName: '新宿現場',
                workContent: '通常勤務',
                quantityLabel: '20日',
                unitPriceYen: 25000,
                amountYen: 500000,
              ),
              PaymentCertificateLine(
                siteName: '新宿現場',
                workContent: '残業',
                quantityLabel: '10時間',
                unitPriceYen: 2500,
                amountYen: 25000,
              ),
            ],
          );
          final bytes = await PaymentCertificatePdfService.buildPdf(
            record,
            regularFont: font,
            boldFont: font,
          );
          final file = File(
            '${output.path}/payment_certificate_company_${i + 1}.pdf',
          )..writeAsBytesSync(bytes);
          final result = await Process.run('python', [
            '-c',
            r'''
import fitz, hashlib, json, sys
d=fitz.open(sys.argv[1]); p=d[0]
pix=p.get_pixmap(matrix=fitz.Matrix(2,2), alpha=False)
samples=pix.samples; channels=pix.n
red=bytearray()
for i in range(0,len(samples),channels):
 r,g,b=samples[i:i+3]
 red.append(1 if r>100 and r>g*1.5 and r>b*1.5 else 0)
embedded=sum(bool(d.extract_font(f[0])[3]) for f in p.get_fonts())
print(json.dumps({'pages':len(d),'width':p.rect.width,'height':p.rect.height,
 'text':p.get_text(),'embedded_fonts':embedded,'red_pixels':sum(red),
 'seal_mask':hashlib.sha256(red).hexdigest()},ensure_ascii=False))
''',
            file.path,
          ]);
          expect(result.exitCode, 0, reason: result.stderr.toString());
          final report =
              jsonDecode(result.stdout.toString()) as Map<String, dynamic>;
          reports.add(report);
          expect(report['pages'], 1);
          expect(report['width'], closeTo(595.2756, .01));
          expect(report['height'], closeTo(841.8898, .01));
          expect(report['embedded_fonts'], greaterThan(0));
          expect(report['red_pixels'], greaterThan(100));
          final text = report['text'] as String;
          for (final value in [
            companies[i],
            '株式会社山田建設',
            '新宿現場',
            '通常勤務',
            '残業',
            '525,000',
            '-25,000',
            '¥500,000',
          ]) {
            expect(text, contains(value));
          }
          expect(text, isNot(contains(companies[1 - i])));
          expect(record.netAmount, 500000);
          expect(record.lines.length, 2);
        }
        expect(reports[0]['seal_mask'], isNot(reports[1]['seal_mask']));
      } finally {
        if (configured == null) output.deleteSync(recursive: true);
      }
    },
    skip: fontPath == null
        ? 'Set SKO_PDF_FONT_PATH to an embedded Japanese TTF.'
        : false,
  );
}
