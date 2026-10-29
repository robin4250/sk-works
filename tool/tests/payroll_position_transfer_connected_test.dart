// Disposable PG output -> unchanged real renderer. Never fetches live payroll.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/features/payroll/payroll_pdf_service.dart';
import 'package:sk_works/features/payroll/payroll_position_transfer.dart';
import 'package:sk_works/features/payroll/payroll_statement_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('UI-equivalent saved payload -> actual PG sync -> saved detail -> actual PDF', () async {
    // Dedicated CI must provision all three; absence is a failure, never a skip.
    final fixturePath = Platform.environment['SKO_TRANSFER_CONNECTED_JSON'];
    final fontPath = Platform.environment['SKO_PDF_FONT_PATH'];
    final outputPath = Platform.environment['SKO_PDF_OUTPUT_DIR'];
    expect(fixturePath, isNotNull, reason: 'Disposable native SQL output is required');
    expect(fontPath, isNotNull, reason: 'Real Japanese font is required');
    expect(outputPath, isNotNull, reason: 'PDF evidence output is required');
    final fixture = jsonDecode(await File(fixturePath!).readAsString()) as Map<String, dynamic>;
    final payload = jsonDecode(await File('test/fixtures/payroll_transfer/ui-save-equivalent.json').readAsString());
    expect(fixture['ui_payload'], payload);
    final rows = fixture['statements'] as Map<String, dynamic>;
    expect(rows.keys.toSet(), {'daily', 'finalized', 'monthly_saved_enabled', 'invalid_amount'});
    final font = pw.Font.ttf(ByteData.sublistView(await File(fontPath!).readAsBytes()));
    await Directory(outputPath!).create(recursive: true);
    final untouched = jsonEncode(fixture);
    Map<String, Object?> earnings(Map<String, dynamic> detail) => {
      for (final name in ['基本給', '役職手当', '勤務手当', '残業手当']) name: detail[name],
    };
    for (final name in rows.keys) {
      final row = rows[name] as Map<String, dynamic>;
      final detail = Map<String, dynamic>.from(row['detail'] as Map);
      final original = earnings(detail);
      final before = jsonEncode(detail), originalBefore = jsonEncode(original);
      final monthly = name == 'monthly_saved_enabled';
      final invalid = name == 'invalid_amount';
      expect(detail['残業手当'], 25000);
      expect(row['gross_pay'], monthly ? 331000 : 241000);
      expect(row['deductions'], 10000);
      expect(row['net_pay'], monthly ? 321000 : 231000);
      expect(original.values.cast<num>().reduce((a, b) => a + b), row['gross_pay']);
      final transfer = payrollPositionTransfer(detail, original);
      if (monthly || invalid) {
        expect(transfer, isNull);
      } else {
        expect(transfer, isNotNull);
        expect(transfer!.rate, 11000);
        expect(transfer.days, 20);
        expect(transfer.entries['基本給'], 220000);
        expect(transfer.entries['基本給の調整額'], -4000);
        expect(transfer.entries['残業手当'], 25000);
        expect(transfer.entries.values.cast<num>().reduce((a, b) => a + b), row['gross_pay']);
      }
      expect(jsonEncode(original), originalBefore);
      final statement = PayrollStatementRecord(id: 'synthetic-connected-$name',
        companyName: '接続試験専用架空会社', workerName: '接続試験専用架空社員',
        periodStart: DateTime.parse(row['period_start'] as String),
        periodEnd: DateTime.parse(row['period_end'] as String),
        grossPay: row['gross_pay'] as int, deductions: row['deductions'] as int,
        netPay: row['net_pay'] as int, detail: detail);
      final bytes = await PayrollPdfService.buildPdf(statement, regularFont: font, boldFont: font);
      expect(jsonEncode(detail), before);
      final file = File('$outputPath/payroll_position_transfer_connected_$name.pdf');
      await file.writeAsBytes(bytes);
      final result = await Process.run('python3', ['-c', r'''
import fitz,re,sys,unicodedata
p=fitz.open(sys.argv[1])[0]
p.get_pixmap(matrix=fitz.Matrix(1.5,1.5)).save(sys.argv[1]+'.png')
print(re.sub(r'\s+','',unicodedata.normalize('NFKC',p.get_text())))
''', file.path]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      final text = result.stdout.toString();
      expect(text, contains(monthly ? '331,000' : '241,000'));
      expect(text, contains(monthly ? '321,000' : '231,000'));
      expect(text, contains('25,000')); // Overtime survives both persisted and PDF seams.
      if (monthly || invalid) {
        expect(text, contains('役職手当'));
        expect(text, contains('勤務手当'));
        // Known monthly snapshots remain inapplicable without an error;
        // inconsistent daily transfer must still visibly refuse attribution.
        expect(text, monthly
          ? isNot(contains('振替の設定・支給額を確認してください'))
          : contains('振替の設定・支給額を確認してください'));
        expect(text, isNot(contains('基本給の調整額')));
      } else {
        expect(text, contains('11,000円×20日'));
        expect(text, contains('基本給の調整額'));
        expect(text, contains('-4,000'));
        expect(text, isNot(contains('役職手当')));
        expect(text, isNot(contains('勤務手当')));
      }
    }
    expect(rows['finalized']['detail'], rows['daily']['detail']);
    expect(rows['finalized']['workflow_state'], 'finalized');
    expect(jsonEncode(fixture), untouched);
  });
}
