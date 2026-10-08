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
  final hasFont = fontPath != null && File(fontPath).existsSync();
  test('actual persisted monthly payroll rows reconcile with PDF money rows', () async {
    final font = pw.Font.ttf(ByteData.sublistView(await File(fontPath!).readAsBytes()));
    final directory = Platform.environment['SKO_PDF_OUTPUT_DIR'] ??
        (await Directory.systemTemp.createTemp('sko-persisted-money-')).path;
    await Directory(directory).create(recursive: true);
    for (final name in ['actual_monthly', 'actual_deduction', 'actual_daily_categories', 'actual_hourly_categories', 'actual_monthly_categories']) {
      final row = jsonDecode(await File('test/fixtures/payroll_persisted_money/$name.json').readAsString()) as Map<String, dynamic>;
      final original = jsonEncode(row);
      final record = PayrollStatementRecord(
        id: name,
        companyName: '登録会社',
        workerName: '登録社員',
        periodStart: DateTime(2026, 8, 1),
        periodEnd: DateTime(2026, 8, 31),
        grossPay: row['gross_pay'] as int,
        deductions: row['deductions'] as int,
        netPay: row['net_pay'] as int,
        detail: Map<String, dynamic>.from(row['detail'] as Map),
      );
      final bytes = await PayrollPdfService.buildPdf(record, regularFont: font, boldFont: font);
      final file = File('$directory/payroll_persisted_$name.pdf');
      await file.writeAsBytes(bytes);
      final inspected = await Process.run('python', ['-c', r'''
import fitz,json,sys,re
p=fitz.open(sys.argv[1])[0]
s=[s for b in p.get_text('dict')['blocks'] for l in b.get('lines',[]) for s in l['spans']]
rows=[v for v in s if 321<=v['bbox'][1]<541]
def money(left,right):
 return sum(int(v['text'].replace(',','')) for v in rows if left<=v['bbox'][0] and v['bbox'][2]<=right and re.fullmatch(r'[0-9,]+',v['text']))
print(json.dumps({'earnings':money(240,293),'deductions':money(490,558),'labels':[v['text'] for v in rows if v['bbox'][0]<110 or 302<=v['bbox'][0]<385],'pages':len(fitz.open(sys.argv[1]))},ensure_ascii=False))
''', file.path]);
      expect(inspected.exitCode, 0, reason: inspected.stderr.toString());
      final report = jsonDecode(inspected.stdout.toString()) as Map<String, dynamic>;
      expect(report['pages'], 1);
      expect(report['earnings'], record.grossPay,
          reason: 'Monthly metadata must not become an additional salary item.');
      expect(report['deductions'], record.deductions,
          reason: 'Legacy signed keys mirror registered deductions and must appear once.');
      expect((report['earnings'] as int) - (report['deductions'] as int), record.netPay);
      final labels = (report['labels'] as List<dynamic>).cast<String>();
      expect(labels.where((value) => value == '基本給'), hasLength(1));
      expect(labels.where((value) => value == '残業手当'), hasLength(1));
      expect(labels, isNot(contains('月固定給')));
      if (name == 'actual_deduction' || name.endsWith('_categories')) {
        expect(labels.where((value) => value == '道具代'), hasLength(1));
      }
      if (name.endsWith('_categories')) {
        expect(labels.where((value) => value == '資格手当'), hasLength(1));
        expect(labels.where((value) => value == '交通費'), hasLength(1));
        expect(labels.where((value) => value == '早出手当'), hasLength(1));
      }
      expect(jsonEncode(row), original, reason: 'Rendering cannot rewrite saved financial data.');
    }
  }, skip: !hasFont ? 'Set SKO_PDF_FONT_PATH for actual PDF generation.' : false);
}
