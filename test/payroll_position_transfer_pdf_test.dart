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
  test('actual PDF displays signed rounding adjustment and preserves totals', () async {
    final font = pw.Font.ttf(ByteData.sublistView(await File(fontPath!).readAsBytes()));
    final detail = <String, dynamic>{
      '基本給': 200000, '残業手当': 25000, '役職手当': 11000, '勤務手当': 5000,
      '出勤日数': 20, 'pay_type': 'daily', 'company_seal_enabled': false,
      'position_transfer_snapshot': {'version': 1, 'enabled': true, 'pay_type': 'daily',
        'items': [{'name': '役職手当', 'amount_yen': 11000}, {'name': '勤務手当', 'amount_yen': 5000}]},
      'attendance_unit_evidence': {'contract_version': 1, 'items': [
        {'name': '基本給', 'section': 'earning', 'category': 'day', 'unit': 'day',
          'rate_yen': 10000, 'quantity': 20, 'amount_yen': 200000}]},
    };
    final before = jsonEncode(detail);
    final statement = PayrollStatementRecord(id: 'synthetic-transfer', companyName: '合成会社',
      workerName: '合成社員', periodStart: DateTime(2026, 10, 1),
      periodEnd: DateTime(2026, 10, 31), grossPay: 241000,
      deductions: 10000, netPay: 231000, detail: detail);
    final bytes = await PayrollPdfService.buildPdf(statement, regularFont: font, boldFont: font);
    expect(jsonEncode(detail), before);
    final folder = Platform.environment['SKO_PDF_OUTPUT_DIR'] ??
        (await Directory.systemTemp.createTemp('transfer-pdf-')).path;
    await Directory(folder).create(recursive: true);
    final file = File('$folder/payroll_position_transfer.pdf');
    await file.writeAsBytes(bytes);
    final result = await Process.run('python3', ['-c', r'''
import fitz,re,sys,unicodedata
p=fitz.open(sys.argv[1])[0];p.get_pixmap(matrix=fitz.Matrix(1.5,1.5)).save(sys.argv[1]+'.png')
print(re.sub(r'\s+','',unicodedata.normalize('NFKC',p.get_text())))
''', file.path]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final text = result.stdout.toString();
    expect(text, contains('11,000円×20日'));
    expect(text, contains('基本給の調整額'));
    expect(text, contains('-4,000'));
    expect(text, contains('241,000'));
    expect(text, contains('231,000'));
    expect(text, isNot(contains('役職手当')));
    expect(text, isNot(contains('勤務手当')));
  }, skip: fontPath == null ? 'Requires remote PDF/font proof environment' : false);
}
