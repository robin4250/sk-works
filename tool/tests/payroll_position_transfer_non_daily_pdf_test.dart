// Dedicated font/PDF job only. Not discovered by generic flutter test.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/features/payroll/payroll_pdf_service.dart';
import 'package:sk_works/features/payroll/payroll_statement_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('actual PDFs suppress only valid non-daily warnings and preserve every saved amount', () async {
    final fontPath = Platform.environment['SKO_PDF_FONT_PATH'];
    final outputPath = Platform.environment['SKO_PDF_OUTPUT_DIR'];
    expect(fontPath, isNotNull);
    expect(outputPath, isNotNull);
    final font = pw.Font.ttf(ByteData.sublistView(await File(fontPath!).readAsBytes()));
    await Directory(outputPath!).create(recursive: true);
    Map<String, dynamic> snap(String type) => {'version': 1, 'enabled': true,
      'pay_type': type, 'items': [{'name': '役職手当', 'amount_yen': 11000}]};
    final cases = <String, Map<String, dynamic>>{
      'monthly': snap('monthly'), 'hourly': snap('hourly'),
      'daily_inconsistent': {...snap('daily'), 'items': [{'name': '役職手当', 'amount_yen': 11001}]},
      'unknown': snap('future'),
      'bad_version': {...snap('monthly'), 'version': 2},
      'missing_items': {...snap('monthly')}..remove('items'),
      'negative': {...snap('hourly'), 'items': [{'name': '役職手当', 'amount_yen': -1}]},
      'duplicate': {...snap('monthly'), 'items': [
        {'name': '役職手当', 'amount_yen': 11000}, {'name': ' 役職手当 ', 'amount_yen': 1}]},
      'reserved': {...snap('hourly'), 'items': [{'name': '基本給', 'amount_yen': 200000}]},
    };
    for (final entry in cases.entries) {
      final detail = <String, dynamic>{'基本給': 200000, '役職手当': 11000,
        '残業手当': 25000, 'company_seal_enabled': false,
        'position_transfer_snapshot': entry.value,
        'attendance_unit_evidence': {'contract_version': 1, 'items': [
          {'name': '基本給', 'section': 'earning', 'category': 'monthly',
            'unit': 'month', 'rate_yen': 200000, 'quantity': 1, 'amount_yen': 200000}]}};
      final before = jsonEncode(detail);
      final statement = PayrollStatementRecord(id: 'synthetic-warning-${entry.key}',
        companyName: '警告試験専用架空会社', workerName: '警告試験専用架空社員',
        periodStart: DateTime(2026, 9, 1), periodEnd: DateTime(2026, 9, 30),
        grossPay: 236000, deductions: 10000, netPay: 226000, detail: detail);
      final bytes = await PayrollPdfService.buildPdf(statement, regularFont: font, boldFont: font);
      expect(jsonEncode(detail), before);
      expect(statement.grossPay, 236000);
      expect(statement.deductions, 10000);
      expect(statement.netPay, 226000);
      final file = File('$outputPath/payroll_position_transfer_non_daily_${entry.key}.pdf');
      await file.writeAsBytes(bytes);
      final result = await Process.run('python3', ['-c', r'''
import fitz,re,sys,unicodedata
p=fitz.open(sys.argv[1])[0]
p.get_pixmap(matrix=fitz.Matrix(1.5,1.5)).save(sys.argv[1]+'.png')
print(re.sub(r'\s+','',unicodedata.normalize('NFKC',p.get_text())))
''', file.path]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      final text = result.stdout.toString();
      for (final expected in ['236,000', '226,000', '200,000', '25,000', '11,000', '役職手当']) {
        expect(text, contains(expected), reason: entry.key);
      }
      expect(text, isNot(contains('基本給の調整額')), reason: entry.key);
      final validNonDaily = entry.key == 'monthly' || entry.key == 'hourly';
      expect(text, validNonDaily ? isNot(contains('振替の設定・支給額を確認してください'))
        : contains('振替の設定・支給額を確認してください'), reason: entry.key);
    }
  });
}
