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
  test('paid leave daily earning and monthly allocation use the adopted PDF', () async {
    final font = pw.Font.ttf(ByteData.sublistView(await File(fontPath!).readAsBytes()));
    final directory = Platform.environment['SKO_PDF_OUTPUT_DIR'] ??
        (await Directory.systemTemp.createTemp('paid-leave-pdf-')).path;
    await Directory(directory).create(recursive: true);
    for (final monthly in [false, true]) {
      final detail = <String, dynamic>{
        'company_seal_enabled': false,
        'pay_type': monthly ? 'monthly' : 'daily',
        '基本給': monthly ? 300000 : 12000,
        '有給日数': 1,
        '有給単価': monthly ? 14000 : 12000,
        '有給支給額': monthly ? 0 : 12000,
        '有給内訳額': monthly ? 14000 : 12000,
        'paid_leave_wage_contract': 1,
      };
      final original = jsonEncode(detail);
      final amount = monthly ? 300000 : 24000;
      final record = PayrollStatementRecord(
        id: monthly ? 'monthly-leave' : 'daily-leave',
        companyName: 'SKO建設株式会社', workerName: '有給確認 太郎',
        periodStart: DateTime(2026, 10, 1), periodEnd: DateTime(2026, 10, 31),
        issuedAt: DateTime(2026, 11, 25),
        grossPay: amount, deductions: 0, netPay: amount, detail: detail,
      );
      final pdf = await PayrollPdfService.buildPdf(record, regularFont: font, boldFont: font);
      final file = File('$directory/payroll_paid_leave_${monthly ? 'monthly' : 'daily'}.pdf');
      await file.writeAsBytes(pdf);
      final inspected = await Process.run('python', ['-c',
        'import fitz,json,sys; p=fitz.open(sys.argv[1]); print(json.dumps({"pages":len(p),"text":"".join(x.get_text() for x in p)},ensure_ascii=False))',
        file.path]);
      expect(inspected.exitCode, 0, reason: inspected.stderr.toString());
      final data = jsonDecode(inspected.stdout.toString()) as Map<String, dynamic>;
      expect(data['pages'], 1);
      final text = (data['text'] as String).replaceAll(RegExp(r'\s+'), '');
      expect(RegExp('有給支給額').allMatches(text).length, monthly ? 0 : 1);
      expect(text, isNot(contains('有給単価')));
      expect(text, isNot(contains('有給内訳額')));
      expect(text, isNot(contains('paid_leave_wage_contract')));
      expect(text, contains(monthly ? '300,000' : '24,000'));
      expect(jsonEncode(detail), original);
    }
  }, skip: fontPath == null || !File(fontPath).existsSync()
      ? 'Requires CI Japanese PDF fixture font.' : false);
}
