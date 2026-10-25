import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/features/payroll/payroll_pdf_service.dart';
import 'package:sk_works/features/payroll/payroll_statement_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final source = Platform.environment['SKO_PAID_HOURS_EXPORT'];
  final fontPath = Platform.environment['SKO_PDF_FONT_PATH'];
  test('actual signed-hour payroll maps and prints identical saved money', () async {
    final data = jsonDecode(await File(source!).readAsString()) as Map<String, dynamic>;
    expect(data['synthetic_only'], true);
    final original = jsonEncode(data);
    final row = Map<String, dynamic>.from(data['client_rpc_row'] as Map);
    final saved = Map<String, dynamic>.from(data['saved_statement'] as Map);
    final expected = Map<String, dynamic>.from(data['expected'] as Map);
    final detail = Map<String, dynamic>.from(saved['detail'] as Map);
    final unit = Map<String, dynamic>.from(detail['unit_resolution'] as Map);
    final line = (unit['items'] as List).cast<Map>().singleWhere((r) => r['unit'] == 'hour');
    expect(line['quantity'], expected['hours']);
    expect(line['rate_yen'], expected['rate']);
    expect(line['amount_yen'], expected['allowance']);
    expect(line['quantity_basis'], 'dual_signed_closed_day_ledger');
    expect(line['hours_evidence'], isNotEmpty);
    final statement = payrollStatementFromRow(row, null);
    expect(statement.grossPay, 27250);
    expect(statement.grossPay, saved['gross_pay']);
    expect(statement.deductions, saved['deductions']);
    expect(statement.netPay, saved['net_pay']);
    final font = pw.Font.ttf(ByteData.sublistView(await File(fontPath!).readAsBytes()));
    final output = Directory(Platform.environment['SKO_PDF_OUTPUT_DIR'] ?? 'build/paid-hours-proof');
    await output.create(recursive: true);
    final file = File('${output.path}/signed_paid_hours_payroll.pdf');
    final bytes = await PayrollPdfService.buildPdf(statement, regularFont: font, boldFont: font);
    await file.writeAsBytes(bytes);
    final result = await Process.run('python3', ['-c', r'''
import fitz,json,sys
doc=fitz.open(sys.argv[1]);text='\n'.join(p.get_text() for p in doc)
bad=[s['text'] for p in doc for b in p.get_text('dict')['blocks'] for l in b.get('lines',[]) for s in l['spans'] if s['bbox'][0]<-0.5 or s['bbox'][1]<-0.5 or s['bbox'][2]>p.rect.width+0.5 or s['bbox'][3]>p.rect.height+0.5]
doc[0].get_pixmap(matrix=fitz.Matrix(1.5,1.5)).save(sys.argv[2])
print(json.dumps({'pages':len(doc),'text':text,'outside':bad},ensure_ascii=False))
''', file.path, '${output.path}/signed_paid_hours_payroll.png']);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final parsed = jsonDecode(result.stdout.toString()) as Map<String, dynamic>;
    expect(parsed['outside'], isEmpty);
    final text = parsed['text'] as String;
    expect(text, contains('合成時間手当'));
    expect(RegExp('合成時間手当').allMatches(text), hasLength(1),
      reason: 'One signed daily quantity prints one allowance row.');
    expect(text, contains('7,250'));
    expect(text, contains('7.25時間'));
    expect(text, contains('1,000円'));
    expect(text, contains('27,250'));
    expect(jsonEncode(data), original, reason: 'PDF generation must not rewrite signed calculation evidence.');
  }, skip: source == null || fontPath == null ? 'Dedicated native-to-PDF job supplies actual synthetic source and font.' : false);
}
