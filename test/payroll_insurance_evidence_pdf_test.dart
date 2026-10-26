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
band_top=690 if sys.argv[2]=='paid_leave' else 673
band_bottom=745 if sys.argv[2]=='paid_leave' else 741
evidence=[s for s in spans if band_top<=s['bbox'][1]<749]
names=['健康保険料','厚生年金保険','介護保険料','雇用保険料','子ども・子育て支援金']
visible_names=[name for name in names if any(s['text'].startswith(name+'：') and s['bbox'][3]<=band_bottom for s in evidence)]
report={'pages':len(pdf),'text':p.get_text(),'deductions':deductions,'evidence_bottom':max((s['bbox'][3] for s in evidence),default=0),'visible_evidence_names':visible_names}
p.get_pixmap(matrix=fitz.Matrix(1.5,1.5)).save(sys.argv[1]+'.png')
print(json.dumps(report,ensure_ascii=False))
''', file.path, paidLeave ? 'paid_leave' : 'standard']);
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
      expect(report['visible_evidence_names'], containsAll(['健康保険料', '厚生年金保険', '介護保険料', '雇用保険料', '子ども・子育て支援金']));
      expect(report['evidence_bottom'] as num, lessThan(749), reason: 'Evidence must stay above remarks/bank boxes');
    }
  }, skip: fontPath == null ? 'Uses the existing remote PDF/font verification environment' : false);
  test('actual saved lower and upper bound equations remain printed above bank fields', () async {
    final font = pw.Font.ttf(ByteData.sublistView(await File(fontPath!).readAsBytes()));
    for (final values in [
      (58000, 88000, '標準報酬月額 ¥58,000 × 5% ＝ ¥2,900',
        '標準報酬月額 ¥88,000 × 9.15% ＝ ¥8,052', false),
      (1390000, 650000, '標準報酬月額 ¥1,390,000 × 5% ＝ ¥69,500',
        '標準報酬月額 ¥650,000 × 9.15% ＝ ¥59,475', true),
    ]) {
      final detail = {...insuranceBoundaryEvidenceFixture(healthBase: values.$1, pensionBase: values.$2),
        '基本給': 500000, '所得税': 5000, '住民税': 12000, 'pay_type': 'monthly',
        'company_seal_enabled': false, '備考': '保存済みの計算式と振込先を照合する合成明細',
        'bank_account': {'bank_name': '保存済み振込先銀行', 'bank_branch': '合成支店',
          'bank_account_type': '普通', 'bank_account_number': '0000123', 'bank_account_holder': 'ゴウセイ シャイン'},
        if (values.$5) ...{'有給単価': 10000, '有給日数': 1, '有給内訳額': 10000}};
      final premiums = (detail['tax_calculation'] as Map)['premiums'] as Map;
      final deductions = premiums.values.cast<int>().fold<int>(17000, (a, b) => a + b);
      final before = jsonEncode(detail);
      final statement = PayrollStatementRecord(id: 'insurance-boundary-${values.$1}',
        companyName: '境界照合用の合成会社', workerName: '合成社員',
        periodStart: DateTime(2026, 10, 1), periodEnd: DateTime(2026, 10, 31),
        grossPay: 500000, deductions: deductions.toDouble(), netPay: (500000 - deductions).toDouble(), detail: detail);
      final bytes = await PayrollPdfService.buildPdf(statement, regularFont: font, boldFont: font);
      expect(jsonEncode(detail), before);
      final folder = Platform.environment['SKO_PDF_OUTPUT_DIR'] ??
          (await Directory.systemTemp.createTemp('insurance-boundary-pdf-')).path;
      await Directory(folder).create(recursive: true);
      final file = File('$folder/payroll_insurance_evidence_boundary_${values.$1}.pdf');
      await file.writeAsBytes(bytes);
      final result = await Process.run('python3', ['-c', r'''
import fitz,json,re,sys,unicodedata
pdf=fitz.open(sys.argv[1]);p=pdf[0]
normalize=lambda text: re.sub(r'\s+','',unicodedata.normalize('NFKC',text)).replace('￥','¥')
text=p.get_text();expected=json.loads(sys.argv[3])
spans=[s for b in p.get_text('dict')['blocks'] for l in b.get('lines',[]) for s in l['spans']]
band_top=690 if sys.argv[2]=='paid_leave' else 673
band_bottom=745 if sys.argv[2]=='paid_leave' else 741
evidence=[s for s in spans if band_top<=s['bbox'][1]<749]
formulas=[s for s in evidence if any(s['text'].startswith(n+'：') for n in ['健康保険料','厚生年金保険'])]
bank=[s for s in spans if '保存済み振込先銀行' in s['text']]
report={'pages':len(pdf),'actual_formulas':[normalize(e) in normalize(text) for e in expected],
 'evidence_bottom':max((s['bbox'][3] for s in evidence),default=0),
 'bank_top':min((s['bbox'][1] for s in bank),default=0),
 'formula_font_min':min((s['size'] for s in formulas),default=0),'text':text,'band_bottom':band_bottom}
p.get_pixmap(matrix=fitz.Matrix(1.5,1.5)).save(sys.argv[1]+'.png')
print(json.dumps(report,ensure_ascii=False))
''', file.path, values.$5 ? 'paid_leave' : 'standard', jsonEncode([values.$3, values.$4])]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      final report = jsonDecode(result.stdout.toString()) as Map;
      expect(report['pages'], 1);
      expect(report['actual_formulas'], [true, true]);
      expect(report['formula_font_min'] as num, greaterThanOrEqualTo(5.1));
      expect(report['evidence_bottom'] as num, lessThan(749));
      expect(report['bank_top'] as num, greaterThan(report['evidence_bottom'] as num));
      expect(report['text'], contains('保存済み振込先銀行'));
      expect(report['text'], contains('保存済みの計算式と振込先'));
    }
  }, skip: fontPath == null ? 'Uses the existing remote PDF/font verification environment' : false);

}
