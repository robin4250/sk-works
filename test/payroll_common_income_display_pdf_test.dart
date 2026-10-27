import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/features/payroll/payroll_pdf_service.dart';
import 'package:sk_works/features/payroll/payroll_statement_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fontPath = Platform.environment['SKO_PDF_FONT_PATH'];
  for (final paidLeave in [false, true]) {
  test('common allowance and full income formula fit actual PDF with paid leave=$paidLeave', () async {
    final font = pw.Font.ttf(ByteData.sublistView(await File(fontPath!).readAsBytes()));
    final detail = <String, dynamic>{
      '基本給': 420000, '健康保険料': 20000, '厚生年金保険': 40000,
      '介護保険料': 4000, '雇用保険料': 2000, '子ども・子育て支援金': 1000, '所得税': 7020,
      '出勤日数': 21, 'pay_type': 'daily', 'company_seal_enabled': false,
      'custom_earnings': [{'name': '合成共通手当', 'amount_yen': 3600}],
      'unit_resolution': {'contract_version': 1, 'blocked': false, 'items': [
        {'id': 'unused', 'name': '合成共通手当', 'section': 'earning',
         'unit': 'day', 'quantity': 0, 'rate_yen': 800, 'amount_yen': 0},
        {'id': 'used', 'name': '合成共通手当', 'section': 'earning',
         'origin': 'company_common', 'unit': 'day', 'quantity': 3,
         'rate_yen': 1200, 'amount_yen': 3600},
      ]},
      'tax_calculation': {
        'calculator_version': 'payroll-tax-20261014-overrides-v1',
        'condition_version': 1, 'conditions_start': '2026-01-01',
        'payment_date': '2026-10-25', 'income_table': 'nta-monthly-2026-c583c9c3',
        'gross_with_adjustments': 423600, 'social_yen': 67000,
        'income_tax_base_yen': 356600, 'income_tax_yen': 7020,
        'automatic_income_tax_yen': 7020, 'deduction_overrides': <String, dynamic>{},
        'premiums': {'健康保険料': 20000, '厚生年金保険': 40000, '介護保険料': 4000,
          '雇用保険料': 2000, '子ども・子育て支援金': 1000}, 'rates': [],
        'conditions': {'income_mode': 'koh', 'dependents': 2,
          'insurance_mode': 'manual', 'non_taxable_yen': 0,
          'health': true, 'pension': true, 'employment': true, 'nursing': true, 'child_support': true,
          'manual_insurance_premiums': {'health_insurance': 20000, 'pension_insurance': 40000,
            'nursing_insurance': 4000, 'employment_insurance': 2000, 'child_support': 1000},
          'insurance_basis_reference': {'schema': 1, 'from': '2026-04-01', 'to': '2026-06-01',
            'average_monthly_income_yen': 500000, 'source': 'manual',
            'observed_months': 0, 'history_fingerprint': null},
          'additional_social_deduction_yen': 0},
      },
    };
    if (paidLeave) {
      detail.addAll({'pay_type': 'monthly', '有給単価': 10000, '有給日数': 1, '有給内訳額': 10000});
    }
    final before = jsonEncode(detail);
    final record = PayrollStatementRecord(id: 'synthetic-common-income',
      companyName: '合成会社', workerName: '合成社員',
      periodStart: DateTime(2026, 9, 1), periodEnd: DateTime(2026, 9, 30),
      grossPay: 423600, deductions: 74020, netPay: 349580, detail: detail);
    final bytes = await PayrollPdfService.buildPdf(record,
      regularFont: font, boldFont: font);
    expect(jsonEncode(detail), before);
    final folder = Platform.environment['SKO_PDF_OUTPUT_DIR'] ??
      (await Directory.systemTemp.createTemp('common-income-pdf-')).path;
    await Directory(folder).create(recursive: true);
    final file = File('$folder/payroll_common_income_evidence${paidLeave ? '_paid_leave' : ''}.pdf');
    await file.writeAsBytes(bytes);
    final result = await Process.run('python3', ['-c', r'''
import fitz,json,re,sys,unicodedata
pdf=fitz.open(sys.argv[1]);p=pdf[0]
spans=[s for b in p.get_text('dict')['blocks'] for l in b.get('lines',[]) for s in l['spans']]
rows=[s for s in spans if 321<=s['bbox'][1]<541]
money=lambda left,right:sum(int(s['text'].replace(',','')) for s in rows if left<=s['bbox'][0] and s['bbox'][2]<=right and re.fullmatch(r'[0-9,]+',s['text']))
norm=lambda s:re.sub(r'\s+','',unicodedata.normalize('NFKC',s))
p.get_pixmap(matrix=fitz.Matrix(1.5,1.5)).save(sys.argv[1]+'.png')
formula=[s for s in spans if '所得税対象額' in s['text'] or '令和8年月額表' in s['text']]
evidence=[s for s in spans if 673<=s['bbox'][1]<749]
print(json.dumps({'pages':len(pdf),'text':norm(p.get_text()),'earnings':money(240,293),'deductions':money(490,558),
 'formula_font_min':min((s['size'] for s in formula),default=0),
 'evidence_bottom':max((s['bbox'][3] for s in evidence),default=0)},ensure_ascii=False))
''', file.path]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final report = jsonDecode(result.stdout.toString()) as Map;
    expect(report['pages'], 1);
    expect(report['text'], contains('1,200円×3日'));
    expect(report['text'], contains('対象356,600円/R8月額表甲欄・扶養2人'));
    expect(report['text'], contains('所得税対象額:支給額423,600円−非課税額0円−社会保険料等67,000円−他項目で控除済みの社会保険料等0円=356,600円'));
    expect(report['text'], contains('令和8年月額表:甲欄・扶養2人、対象356,600円→自動計算7,020円'));
    expect(report['text'], contains('349,580'));
    expect(report['formula_font_min'] as num, greaterThanOrEqualTo(5.1));
    expect(report['evidence_bottom'] as num, lessThan(749));
    expect(report['text'], contains('R8.4〜R8.6'));
    if (paidLeave) expect(report['text'], contains('有給内訳'));
    expect(report['earnings'], 423600);
    expect(report['deductions'], 74020);
  }, skip: fontPath == null ? 'Requires remote PDF/font proof environment' : false);
  }
}
