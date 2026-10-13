import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/features/payroll/payment_certificate_pdf_service.dart';
import 'package:sk_works/features/payroll/payment_certificate_repository.dart';
import 'package:sk_works/features/shared/company_seal_pdf.dart';
import 'package:sk_works/domain/company_seal_design.dart';
import 'package:sk_works/domain/company_seal_snapshot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fontPath = Platform.environment['SKO_PDF_FONT_PATH'];

  test('short seal columns preserve right-to-left reading order', () {
    expect(CompanySealPdf.verticalColumns('親会社'), ['親', '会', '社']);
  });

  test(
    'only unambiguous postal and metropolitan phone digits are formatted',
    () {
      expect(
        PaymentCertificatePdfService.formatPostalCode('1300003'),
        '130-0003',
      );
      expect(
        PaymentCertificatePdfService.formatPostalCode('130-0003'),
        '130-0003',
      );
      expect(PaymentCertificatePdfService.formatPostalCode('130003'), '130003');
      expect(
        PaymentCertificatePdfService.formatPhone('0336333110'),
        '03-3633-3110',
      );
      expect(
        PaymentCertificatePdfService.formatPhone('0612345678'),
        '06-1234-5678',
      );
      for (final value in [
        '09012345678',
        '0451234567',
        '+81 3 3633 3110',
        '03-3633-3110',
      ]) {
        expect(PaymentCertificatePdfService.formatPhone(value), value);
      }
    },
  );

  test(
    'company label remains readable with registered seal overlay',
    () async {
      final configured = Platform.environment['SKO_PDF_OUTPUT_DIR'];
      final output = configured == null
          ? Directory.systemTemp.createTempSync('sko-certificate-header-')
          : Directory(configured);
      output.createSync(recursive: true);
      final font = pw.Font.ttf(
        ByteData.sublistView(await File(fontPath!).readAsBytes()),
      );
      try {
        const names = ['親会社', '株式会社首都圏建設設備保守管理および共同現場工事支援'];
        for (var i = 0; i < 6; i++) {
          final name = i >= 4 ? 'すみだ建設株式会社' : names[i ~/ 2];
          final png = i == 5;
          final enabled = png || i.isEven;
          final record = PaymentCertificateRecord(
            id: 'header-$i',
            companySealSnapshot: png
                ? CompanySealSnapshot.fromJson({
                    'version': 1,
                    'style': 'png_sumida_v1_standard',
                    'name': CompanySealDesign.companyName,
                    'company_id': CompanySealDesign.companyId,
                  })
                : CompanySealSnapshot.fromJson(null),
            partnerCompanyName: '検証用下請会社',
            payerCompanyName: name,
            payerCompanySealEnabled: enabled,
            payerPostalCode: i >= 4 ? '1300003' : '160-0022',
            payerAddress: i >= 4 ? '東京都墨田区横川1-9-1' : '東京都新宿区新宿1-2-3（検証用）',
            payerPhone: i >= 4 ? '0336333110' : '03-0000-0011',
            payerFax: '03-0000-0012',
            periodStart: DateTime(2026, 10),
            periodEnd: DateTime(2026, 10, 31),
            grossAmount: 20000,
            deductions: 0,
            netAmount: 20000,
            status: 'draft',
            revision: 1,
            lines: const [
              PaymentCertificateLine(
                siteName: '共同工事現場',
                workContent: '請け負い（税別）',
                quantityLabel: '一式',
                unitPriceYen: 20000,
                amountYen: 20000,
              ),
            ],
          );
          final bytes = await PaymentCertificatePdfService.buildPdf(
            record,
            regularFont: font,
            boldFont: font,
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
lines=[{'text': ''.join(s['text'] for s in l['spans']), 'bbox':l['bbox']} for b in p.get_text('dict')['blocks'] if 'lines' in b for l in b['lines'] if all(s['color']!=0xff0000 for s in l['spans'])]
images=[list(r) for image in p.get_images() for r in p.get_image_rects(image[0])]
print(json.dumps({'text':p.get_text(),'red_count':len(red),'lines':lines,'red_boxes':[s['bbox'] for s in red],'image_boxes':images},ensure_ascii=False))''',
            '$stem.pdf',
            '$stem.png',
          ]);
          expect(checked.exitCode, 0, reason: checked.stderr.toString());
          final report = jsonDecode(checked.stdout.toString()) as Map;
          final text = (report['text'] as String).replaceAll(
            RegExp(r'\s+'),
            '',
          );
          expect(text, contains(name));
          expect(text, contains(record.payerAddress));
          expect(
            text,
            contains(
              PaymentCertificatePdfService.formatPhone(record.payerPhone),
            ),
          );
          expect(
            text,
            contains(
              '〒${PaymentCertificatePdfService.formatPostalCode(record.payerPostalCode)}',
            ),
          );
          expect(text, contains(record.payerFax));
          expect((report['red_count'] as num) > 0, enabled && !png);
          expect((report['image_boxes'] as List).isNotEmpty, png);
          if (png) {
            final image = (report['image_boxes'] as List).single as List;
            expect((image[2] as num) - (image[0] as num), closeTo(55, 0.5));
            expect((image[3] as num) - (image[1] as num), closeTo(55, 0.5));
          }
          final rows = (report['lines'] as List).cast<Map>();
          Map issuerLine(String value) => rows.singleWhere(
            (row) =>
                (row['text'] as String).replaceAll(RegExp(r'\s+'), '') ==
                value.replaceAll(RegExp(r'\s+'), ''),
          );
          final contacts = [
            issuerLine(
              '〒${PaymentCertificatePdfService.formatPostalCode(record.payerPostalCode)}',
            ),
            issuerLine(record.payerAddress),
            issuerLine(
              'TEL${PaymentCertificatePdfService.formatPhone(record.payerPhone)}',
            ),
            issuerLine('FAX${record.payerFax}'),
          ];
          for (var j = 0; j < contacts.length; j++) {
            final box = (contacts[j]['bbox'] as List).cast<num>();
            final firstBox = (contacts.first['bbox'] as List).cast<num>();
            expect(box[2].toDouble(), closeTo(firstBox[2].toDouble(), 0.5));
            if (j > 0) {
              final previous = (contacts[j - 1]['bbox'] as List).cast<num>();
              expect(box[1] - previous[1], greaterThan(0));
              expect(box[1] - previous[1], lessThan(14));
            }
            final tableBox = (issuerLine('作業所名')['bbox'] as List).cast<num>();
            expect(
              box[3],
              lessThan(tableBox[1]),
              reason:
                  'Issuer details must stay above the unchanged detail table',
            );
            if (png) {
              final image = (report['image_boxes'] as List).single as List;
              expect(
                (image[0] as num) - box[2],
                closeTo(5, 0.5),
                reason:
                    'Short company names must use the full shared issuer lane',
              );
            }
            for (final sealBox in [
              ...(report['red_boxes'] as List).cast<List>(),
              ...(report['image_boxes'] as List).cast<List>(),
            ]) {
              expect(
                box[2],
                lessThan((sealBox[0] as num) + 1),
                reason: 'Contact line must stay outside the seal lane',
              );
            }
          }
          if (i >= 4) {
            final nameBox = (issuerLine(name)['bbox'] as List).cast<num>();
            final postalBox = (contacts.first['bbox'] as List).cast<num>();
            expect(
              nameBox[2].toDouble(),
              closeTo(postalBox[2].toDouble(), 0.5),
            );
            expect(postalBox[1] - nameBox[1], inExclusiveRange(0, 16));
          }
        }
      } finally {
        if (configured == null) output.deleteSync(recursive: true);
      }
    },
    skip: fontPath == null
        ? 'Actual PDF header fixtures require the CI font.'
        : false,
  );
}
