import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/features/payroll/payroll_pdf_service.dart';
import 'package:sk_works/features/payroll/payroll_statement_repository.dart';
import 'fixtures/payroll_insurance_evidence_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fontPath = Platform.environment['SKO_PDF_FONT_PATH'];
  test('PDF keeps adopted page, money columns and saved evidence together', () async {
    final font = pw.Font.ttf(ByteData.sublistView(await File(fontPath!).readAsBytes()));
    for (final paidLeave in [false, true]) {
      final detail = {...insuranceEvidenceFixture(), '基本給': 500000,
        '所得税': 5000, '住民税': 12000, 'pay_type': 'monthly', 'company_seal_enabled': false,
        if (paidLeave) ...{'有給単価': 10000, '有給日数': 1, '有給内訳額': 10000}};
      final before = jsonEncode(detail);
      final statement = PayrollStatementRecord(id: 'insurance-evidence-fixture',
        companyName: '根拠確認用会社', workerName: '確認用社員',
        periodStart: DateTime(2026, 10, 1), periodEnd: DateTime(2026, 10, 31),
        grossPay: 500000, deductions: 68530, netPay: 431470, detail: detail);
      final pdf = await PayrollPdfService.buildPdf(statement, regularFont: font, boldFont: font);
      expect(jsonEncode(detail), before);
      final folder = Platform.environment['SKO_PDF_OUTPUT_DIR'] ??
          (await Directory.systemTemp.createTemp('insurance-evidence-pdf-')).path;
      await Directory(folder).create(recursive: true);
      final file = File('$folder/payroll_insurance_evidence_${paidLeave ? 'paid_leave' : 'standard'}.pdf');
      await file.writeAsBytes(pdf);
      final result = await Process.run('python3', ['-c', r'''
import fitz,json,re,sys
pdf=fitz.open(sys.argv[1]);p=pdf[0]
spans=[s for b in p.get_text('dict')['blocks'] for l in b.get('lines',[]) for s in l['spans']]
rows=[s for s in spans if 321<=s['bbox'][1]<541]
deductions=sum(int(s['text'].replace(',','')) for s in rows if 490<=s['bbox'][0] and s['bbox'][2]<=558 and re.fullmatch(r'[0-9,]+',s['text']))
evidence=[s for s in spans if 670<=s['bbox'][1]<749]
report={'pages':len(pdf),'text':p.get_text(),'deductions':deductions,'evidence_bottom':max((s['bbox'][3] for s in evidence),default=0)}
p.get_pixmap(matrix=fitz.Matrix(1.5,1.5)).save(sys.argv[1]+'.png')
print(json.dumps(report,ensure_ascii=False))
''', file.path]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      final report = jsonDecode(result.stdout.toString()) as Map;
      expect(report['pages'], 1);
      expect(report['deductions'], 68530);
      expect(report['text'], contains('保険料の計算根拠'));
      expect(report['text'], contains('R8.4〜R8.6'));
      expect(report['text'], contains('4.925%'));
      expect(report['text'], contains('9.15%'));
      expect(report['text'], contains('431,470'));
      if (paidLeave) expect(report['text'], contains('有給内訳'));
      expect(report['evidence_bottom'] as num, lessThan(750), reason: 'Evidence must stay above remarks/bank boxes');
    }
  }, skip: fontPath == null ? 'Uses the existing remote PDF/font verification environment' : false);
}
