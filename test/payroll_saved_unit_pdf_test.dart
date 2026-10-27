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
  test('saved unit evidence and non-enrollment remain legible inside adopted PDF', () async {
    final font = pw.Font.ttf(ByteData.sublistView(await File(fontPath!).readAsBytes()));
    final detail = {...insuranceEvidenceFixture(), '基本給': 272000,
      '合成手当': 2100, '出勤日数': 17, 'pay_type': 'daily',
      'company_seal_enabled': false, '備考': '合成検証・保存金額は変更しない',
      '雇用保険料': 0,
      'attendance_unit_evidence': {
        'contract_version': 1, 'blocked': false, 'items': [
          {'name': '基本給', 'section': 'earning', 'unit': 'day',
           'quantity': 17, 'rate_yen': 16000, 'amount_yen': 272000},
          {'name': '合成手当', 'section': 'earning', 'unit': 'day',
           'quantity': 3, 'rate_yen': 700, 'amount_yen': 2100},
        ],
      }};
    final tax = detail['tax_calculation'] as Map;
    (tax['conditions'] as Map)['employment'] = false;
    final before = jsonEncode(detail);
    final statement = PayrollStatementRecord(id: 'synthetic-unit-evidence',
      companyName: '単価検証用合成会社', workerName: '合成社員',
      periodStart: DateTime(2026, 10, 1), periodEnd: DateTime(2026, 10, 31),
      grossPay: 274100, deductions: 49830, netPay: 224270, detail: detail);
    final bytes = await PayrollPdfService.buildPdf(statement, regularFont: font, boldFont: font);
    expect(jsonEncode(detail), before);
    final folder = Platform.environment['SKO_PDF_OUTPUT_DIR'] ??
      (await Directory.systemTemp.createTemp('unit-evidence-pdf-')).path;
    await Directory(folder).create(recursive: true);
    final file = File('$folder/payroll_saved_unit_evidence.pdf');
    await file.writeAsBytes(bytes);
    final result = await Process.run('python3', ['-c', r'''
import fitz,json,re,sys,unicodedata
pdf=fitz.open(sys.argv[1]);p=pdf[0];text=p.get_text()
norm=lambda s:re.sub(r'\s+','',unicodedata.normalize('NFKC',s))
spans=[s for b in p.get_text('dict')['blocks'] for l in b.get('lines',[]) for s in l['spans']]
evidence=[s for s in spans if 673<=s['bbox'][1]<749]
p.get_pixmap(matrix=fitz.Matrix(1.5,1.5)).save(sys.argv[1]+'.png')
print(json.dumps({'pages':len(pdf),'text':norm(text),
 'evidence_names':[s['text'] for s in evidence],
 'bottom':max((s['bbox'][3] for s in evidence),default=0)},ensure_ascii=False))
''', file.path]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final report = jsonDecode(result.stdout.toString()) as Map;
    expect(report['pages'], 1);
    expect(report['text'], contains('16,000円×17日'));
    expect(report['text'], contains('700円×3日'));
    expect(report['text'], contains('224,270'));
    expect(report['text'], isNot(contains('加入対象外')));
    expect((report['evidence_names'] as List).any((s) => s.toString().startsWith('雇用保険料：')), isFalse);
    expect(report['bottom'] as num, lessThan(749));
  }, skip: fontPath == null ? 'Requires remote PDF/font proof environment' : false);
}

