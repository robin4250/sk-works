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
  test('actual SQL common allowance survives RPC mapping and PDF without double payment', () async {
    final fixture = jsonDecode(await File(
      'test/fixtures/company_common_canonical_payroll_flow.json',
    ).readAsString()) as Map<String, dynamic>;
    expect(fixture['synthetic_only'], true);
    final row = Map<String, dynamic>.from(fixture['client_rpc_row'] as Map);
    final saved = Map<String, dynamic>.from(fixture['saved_statement'] as Map);
    final expected = Map<String, dynamic>.from(fixture['expected'] as Map);
    final original = jsonEncode(fixture);
    final statement = payrollStatementFromRow(row, null);
    expect(statement.id, saved['id']);
    expect(statement.revision, saved['revision']);
    expect(statement.isDraft, true);
    expect(statement.grossPay, saved['gross_pay']);
    expect(statement.deductions, saved['deductions']);
    expect(statement.netPay, saved['net_pay']);
    expect(statement.grossPay, expected['gross_pay']);
    expect(statement.deductions, expected['deductions']);
    expect(statement.netPay, expected['net_pay']);
    expect(statement.grossPay - statement.deductions, statement.netPay);
    expect(expected['common_earning_yen'], 1200);
    final font = pw.Font.ttf(ByteData.sublistView(await File(fontPath!).readAsBytes()));
    final directory = Platform.environment['SKO_PDF_OUTPUT_DIR'] ??
        (await Directory.systemTemp.createTemp('sko-common-payroll-flow-')).path;
    await Directory(directory).create(recursive: true);
    final bytes = await PayrollPdfService.buildPdf(statement, regularFont: font, boldFont: font);
    final file = File('$directory/common_payroll_actual_sql.pdf');
    await file.writeAsBytes(bytes);
    final parsed = await Process.run('python3', ['-c', r'''
import fitz,json,re,sys
doc=fitz.open(sys.argv[1]); spans=[s for p in doc for b in p.get_text('dict')['blocks'] for l in b.get('lines',[]) for s in l['spans']]
rows=[v for v in spans if 321<=v['bbox'][1]<541]
def money(left,right):
 return sum(int(v['text'].replace(',','')) for v in rows if left<=v['bbox'][0] and v['bbox'][2]<=right and re.fullmatch(r'[0-9,]+',v['text']))
bad=[s['text'] for p in doc for b in p.get_text('dict')['blocks'] for l in b.get('lines',[]) for s in l['spans'] if s['bbox'][0]<-0.5 or s['bbox'][1]<-0.5 or s['bbox'][2]>p.rect.width+0.5 or s['bbox'][3]>p.rect.height+0.5]
print(json.dumps({'pages':len(doc),'earnings':money(240,293),'deductions':money(490,558),'labels':[v['text'] for v in rows if v['bbox'][0]<110 or 302<=v['bbox'][0]<385],'outside':bad},ensure_ascii=False))
''', file.path]);
    expect(parsed.exitCode, 0, reason: parsed.stderr.toString());
    final report = jsonDecode(parsed.stdout.toString()) as Map<String, dynamic>;
    expect(report['pages'], 1);
    expect(report['outside'], isEmpty);
    expect(report['earnings'], statement.grossPay);
    expect(report['deductions'], statement.deductions);
    expect((report['earnings'] as int) - (report['deductions'] as int), statement.netPay);
    final labels = (report['labels'] as List).cast<String>();
    expect(labels.where((label) => label == 'Synthetic travel'), hasLength(1));
    expect(jsonEncode(fixture), original, reason: 'Mapping and rendering must retain saved amounts and evidence.');
    if (Platform.environment['SKO_COMMON_PUBLIC_PDF_LOG'] == '1') {
      expect(bytes.length, lessThan(160000), reason: 'Only a bounded synthetic PDF may be exported in this proof.');
      stdout.writeln('SKO_COMMON_PUBLIC_PDF_SHA256_FOLLOWS');
      final hash = await Process.run('python3', ['-c', 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())', file.path]);
      expect(hash.exitCode, 0);
      stdout.writeln(hash.stdout.toString().trim());
      stdout.writeln('SKO_COMMON_PUBLIC_PDF_BASE64_START');
      final encoded = base64Encode(bytes);
      for (var offset = 0; offset < encoded.length; offset += 1024) {
        final end = offset + 1024 < encoded.length ? offset + 1024 : encoded.length;
        stdout.writeln(encoded.substring(offset, end));
      }
      stdout.writeln('SKO_COMMON_PUBLIC_PDF_BASE64_END');
    }
  }, skip: fontPath == null ? 'The dedicated PDF job supplies a verified Japanese font.' : false);
}
