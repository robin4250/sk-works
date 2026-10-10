import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/features/payroll/payroll_pdf_service.dart';
import 'package:sk_works/features/payroll/payroll_statement_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PayrollStatementRecord record(Map<String, dynamic> data) =>
      PayrollStatementRecord(
        id: 'tax-fixture',
        companyName: '税額確認用会社',
        workerName: '確認用社員',
        periodStart: DateTime(2026, 9, 1),
        periodEnd: DateTime(2026, 9, 30),
        grossPay: data['gross_pay'] as int,
        deductions: data['deductions'] as int,
        netPay: data['net_pay'] as int,
        detail: Map<String, dynamic>.from(data['detail'] as Map),
      );
  test(
    'incomplete tax calculation cannot be exported as a payroll PDF',
    () async {
      final row = {
        'gross_pay': 300000,
        'deductions': 0,
        'net_pay': 300000,
        'detail': {
          'tax_calculation': {
            'blocked': true,
            'reason': 'fixture missing year',
          },
        },
      };
      await expectLater(
        PayrollPdfService.buildPdf(record(row)),
        throwsStateError,
      );
    },
  );
  final fontPath = Platform.environment['SKO_PDF_FONT_PATH'];
  test(
    'persisted automatic taxes reconcile with actual PDF rows',
    () async {
      final row =
          jsonDecode(
                await File(
                  'test/fixtures/payroll_tax_connection/automatic.json',
                ).readAsString(),
              )
              as Map<String, dynamic>;
      final font = pw.Font.ttf(
        ByteData.sublistView(await File(fontPath!).readAsBytes()),
      );
      final bytes = await PayrollPdfService.buildPdf(
        record(row),
        regularFont: font,
        boldFont: font,
      );
      final dir =
          Platform.environment['SKO_PDF_OUTPUT_DIR'] ??
          (await Directory.systemTemp.createTemp('sko-tax-pdf-')).path;
      await Directory(dir).create(recursive: true);
      final file = File('$dir/payroll_automatic_tax.pdf');
      await file.writeAsBytes(bytes);
      final result = await Process.run('python', [
        '-c',
        r'''
import fitz,json,re,sys
pdf=fitz.open(sys.argv[1]);p=pdf[0]
s=[s for b in p.get_text('dict')['blocks'] for l in b.get('lines',[]) for s in l['spans']]
rows=[v for v in s if 321<=v['bbox'][1]<541]
n=sum(int(v['text'].replace(',','')) for v in rows if 490<=v['bbox'][0] and v['bbox'][2]<=558 and re.fullmatch(r'[0-9,]+',v['text']))
earnings=sum(int(v['text'].replace(',','')) for v in rows if 240<=v['bbox'][0] and v['bbox'][2]<=293 and re.fullmatch(r'[0-9,]+',v['text']))
print(json.dumps({'earnings':earnings,'total':n,'text':p.get_text(),'pages':len(pdf)},ensure_ascii=False))
p.get_pixmap(matrix=fitz.Matrix(1.5,1.5)).save(sys.argv[1]+'.png')
''',
        file.path,
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      final report = jsonDecode(result.stdout.toString()) as Map;
      expect(
        report['earnings'],
        row['gross_pay'],
        reason: 'Insurance deductions must never become earnings',
      );
      expect(report['total'], row['deductions']);
      expect(report['pages'], 1);
      for (final label in [
        '健康保険料',
        '介護保険料',
        '厚生年金保険',
        '雇用保険料',
        '子ども・子育て支援金',
        '所得税',
        '住民税',
      ]) {
        expect(report['text'], contains(label));
      }
    },
    skip: fontPath == null
        ? 'Set SKO_PDF_FONT_PATH and Python with PyMuPDF for PDF verification.'
        : false,
  );
}
