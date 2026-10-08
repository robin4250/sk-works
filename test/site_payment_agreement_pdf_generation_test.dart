import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/features/payroll/payment_certificate_pdf_service.dart';
import 'package:sk_works/features/payroll/site_payment_agreement_document.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fontPath = Platform.environment['SKO_PDF_FONT_PATH'];

  test('accepted agreement snapshots generate the actual certificate PDF',
      () async {
    final configured = Platform.environment['SKO_PDF_OUTPUT_DIR'];
    final output = configured == null
        ? Directory.systemTemp.createTempSync('sko-agreement-pdf-')
        : Directory(configured);
    output.createSync(recursive: true);
    try {
      final jsonFile = File('${output.path}/payment_agreement_snapshots.json');
      final module = Platform.environment['SKO_PAYMENT_PGLITE_PATH'] ??
          '${Platform.environment['RUNNER_TEMP']}/sko-sql-runtime/'
              'node_modules/@electric-sql/pglite/dist/index.js';
      final generated = await Process.run('node', [
        'tool/verify_site_payment_agreement.mjs', module,
      ], environment: {'SKO_SITE_PAYMENT_OUTPUT_JSON': jsonFile.path});
      expect(generated.exitCode, 0, reason: generated.stderr.toString());
      final snapshots = jsonDecode(jsonFile.readAsStringSync()) as List;
      expect(snapshots, hasLength(4));
      final font = pw.Font.ttf(
        ByteData.sublistView(await File(fontPath!).readAsBytes()),
      );
      for (var i = 0; i < snapshots.length; i++) {
        final snapshot = Map<String, dynamic>.from(snapshots[i] as Map);
        final terms = Map<String, dynamic>.from(snapshot['terms'] as Map);
        final record = SitePaymentAgreementDocument.fromSnapshot(snapshot);
        final bytes = await PaymentCertificatePdfService.buildPdf(
          record, regularFont: font, boldFont: font,
        );
        final pdf = File('${output.path}/payment_agreement_${i + 1}.pdf')
          ..writeAsBytesSync(bytes);
        final png = '${output.path}/payment_agreement_${i + 1}.png';
        final result = await Process.run('python', [
          '-c',
          'import fitz,json,sys; d=fitz.open(sys.argv[1]); '
              'assert len(d)==1; p=d[0]; '
              'p.get_pixmap(matrix=fitz.Matrix(2,2),alpha=False).save(sys.argv[2]); '
              'print(json.dumps({"text":p.get_text(),"width":p.rect.width,'
              '"height":p.rect.height},ensure_ascii=False))',
          pdf.path, png,
        ]);
        expect(result.exitCode, 0, reason: result.stderr.toString());
        final report = jsonDecode(result.stdout.toString()) as Map;
        expect(report['width'], closeTo(595.2756, .01));
        expect(report['height'], closeTo(841.8898, .01));
        final text = (report['text'] as String).replaceAll(RegExp(r'\s+'), '');
        expect(text, contains(snapshot['parent_company_name'].toString()));
        expect(text, contains(snapshot['subcontractor_company_name'].toString()));
        expect(text, contains(snapshot['site_name'].toString()));
        expect(text, contains(terms['mode'] == 'square_meter' ? '平米計算' : '請け負い'));
        for (final raw in terms['adjustments'] as List) {
          final item = raw as Map;
          expect(text, contains(item['name'].toString()));
        }
        expect(record.netAmount, terms['final_amount_yen']);
        expect(record.lines.fold<int>(0, (sum, line) => sum + line.amountYen),
            record.netAmount);
        expect(record.lines.any((line) => line.workContent == '消費税'),
            terms['tax_included'] != true);
        for (final premium in ['残業', '早出', '夜勤', '休日出勤']) {
          expect(record.lines.any((line) => line.workContent == premium), false);
          expect(text, isNot(contains(premium)));
        }
        if (i >= 2) {
          expect(terms['adjustments'], hasLength(4));
          expect(record.lines.any((line) =>
              line.workContent == '福利厚生費' && line.amountYen == -500), true);
        }
        // Later mutable source data cannot alter the materialized PDF record.
        final originalName = record.payerCompanyName;
        snapshot['parent_company_name'] = '変更後の会社名';
        expect(record.payerCompanyName, originalName);
        final invalid = Map<String, dynamic>.from(terms)
          ..['final_amount_yen'] = record.netAmount + 1;
        expect(() => SitePaymentAgreementDocument.fromSnapshot({
          ...snapshot, 'terms': invalid,
        }), throwsStateError);
      }
    } finally {
      if (configured == null) output.deleteSync(recursive: true);
    }
  }, skip: fontPath == null
      ? 'Requires the embedded Japanese font and SQL fixture runtime in CI.'
      : false);
}
