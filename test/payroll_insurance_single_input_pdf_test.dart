import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/features/payroll/payroll_pdf_service.dart';
import 'package:sk_works/features/payroll/payroll_statement_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final folder = Platform.environment['SKO_INSURANCE_E2E_DIR'];
  final fontPath = Platform.environment['SKO_PDF_FONT_PATH'];
  test('one-input actual SQL statement matches PDF deduction rows and totals', () async {
    final row = jsonDecode(await File('$folder/statement.json').readAsString()) as Map<String, dynamic>;
    final record = PayrollStatementRecord(id: row['id'] as String,
      companyName: '隔離検証用会社', workerName: '隔離検証用社員',
      periodStart: DateTime(2026, 10, 1), periodEnd: DateTime(2026, 10, 31),
      grossPay: row['gross_pay'] as int, deductions: row['deductions'] as int,
      netPay: row['net_pay'] as int, detail: {...row['detail'] as Map<String, dynamic>, 'company_seal_enabled': false});
    final font = pw.Font.ttf(ByteData.sublistView(await File(fontPath!).readAsBytes()));
    final before = jsonEncode(record.detail);
    final bytes = await PayrollPdfService.buildPdf(record, regularFont: font, boldFont: font);
    expect(jsonEncode(record.detail), before);
    final pdfPath = '$folder/insurance_single_input.pdf';
    await File(pdfPath).writeAsBytes(bytes);
    final result = await Process.run('python3', ['-c', r'''
import fitz,json,re,sys
pdf=fitz.open(sys.argv[1]);p=pdf[0]
spans=[s for b in p.get_text('dict')['blocks'] for l in b.get('lines',[]) for s in l['spans']]
rows=[v for v in spans if 321<=v['bbox'][1]<541]
amounts=[int(v['text'].replace(',','')) for v in rows if 490<=v['bbox'][0] and v['bbox'][2]<=558 and re.fullmatch(r'[0-9,]+',v['text'])]
earnings=sum(int(v['text'].replace(',','')) for v in rows if 240<=v['bbox'][0] and v['bbox'][2]<=293 and re.fullmatch(r'[0-9,]+',v['text']))
report={'deduction_rows':amounts,'deduction_sum':sum(amounts),'earnings_sum':earnings,'text':p.get_text(),'pages':len(pdf)}
p.get_pixmap(matrix=fitz.Matrix(1.5,1.5)).save(sys.argv[1]+'.png')
open(sys.argv[2],'w').write(json.dumps(report,ensure_ascii=False,indent=2))
print(json.dumps(report,ensure_ascii=False))
''', pdfPath, '$folder/pdf-proof.json']);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final report = jsonDecode(result.stdout.toString()) as Map;
    expect(report['pages'], 1);
    expect(report['earnings_sum'], row['gross_pay']);
    expect(report['deduction_sum'], row['deductions']);
    expect(report['deduction_rows'], containsAll([35500, 59475, 5000, 12000]));
    expect(report['text'], contains('健康保険料'));
    expect(report['text'], contains('厚生年金保険'));
    expect(report['text'], contains('588,025'));
    final proofFile = File('$folder/proof.json');
    final proof = jsonDecode(await proofFile.readAsString()) as Map<String, dynamic>;
    proof['pdf_verified'] = true;
    await proofFile.writeAsString(const JsonEncoder.withIndent('  ').convert(proof));
  }, skip: folder == null || fontPath == null ? 'Dedicated disposable PG17 PDF proof pipeline only' : false);
}
