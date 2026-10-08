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
  final outputDirectory = Platform.environment['SKO_PDF_OUTPUT_DIR'];
  final hasFont = fontPath != null && File(fontPath).existsSync();

  test(
    'adopted payroll fixture generates A4 and preserves registered data',
    () async {
      final font = pw.Font.ttf(
        ByteData.sublistView(await File(fontPath!).readAsBytes()),
      );
      final earnings = <Map<String, Object>>[
        for (final item in <String, int>{
          '基本給': 300000,
          '残業手当': 12500,
          '早出手当': 2500,
          '休日出勤手当': 27000,
          '休日残業手当': 6248,
          '資格手当': 10000,
          '現場手当': 5000,
          '皆勤手当': 10000,
          '住宅手当': 20000,
          '家族手当': 10000,
          '役職手当': 0,
          '精勤手当': 5000,
        }.entries)
          {'name': item.key, 'amount_yen': item.value},
      ];
      final deductions = <Map<String, Object>>[
        for (final item in <String, int>{
          '健康保険料': 20000,
          '厚生年金保険料': 36600,
          '雇用保険料': 2000,
          '所得税': 18000,
          '住民税': 10000,
          'SKO会費': 1000,
          '作業着代': 3000,
          '積立金': 5000,
        }.entries)
          {'name': item.key, 'amount_yen': item.value},
      ];
      final detail = <String, dynamic>{
        '社員番号': 'S0001',
        '所属': '建設部',
        '職種': '現場作業員',
        '入社日': '2024年4月1日',
        'pay_type': 'monthly',
        '出勤日数': 20,
        '欠勤日数': 0,
        '有給日数': 1,
        '休出日数': 2,
        '残業時間': 10,
        '早出時間': 2,
        '深夜時間': 0,
        '休日残業時間': 4,
        '休日深夜時間': 0,
        'custom_earnings': earnings,
        'custom_deductions': deductions,
        '残業手当計算内容': '1,250円 × 10.0時間',
        '早出手当計算内容': '1,250円 × 2.0時間',
        '休日出勤手当計算内容': '1,350円 × 2.0日',
        '休日残業手当計算内容': '1,562円 × 4.0時間',
        '資格手当計算内容': '資格手当（登録）',
        '現場手当計算内容': '現場手当（登録）',
        '皆勤手当計算内容': '皆勤手当（登録）',
        '住宅手当計算内容': '住宅手当（登録）',
        '家族手当計算内容': '配偶者・子1人',
        '精勤手当計算内容': '精勤手当',
        '健康保険料計算内容': '標準報酬月額',
        '厚生年金保険料計算内容': '標準報酬月額',
        '雇用保険料計算内容': '標準報酬月額',
        '所得税計算内容': '源泉徴収税額',
        '住民税計算内容': '市町村民税',
        'SKO会費計算内容': '社内会費',
        '作業着代計算内容': '作業着代',
        '積立金計算内容': '積立金',
        '備考': '今月もお疲れ様でした。\nご不明な点がございましたら、総務までお問い合わせください。\n安全第一で、引き続きよろしくお願いいたします。',
        'bank_name': 'SKO銀行',
        'bank_branch': '東京支店',
        'bank_account_type': '普通',
        'bank_account_number': '1234567',
        'bank_account_holder': 'カ）スミダケンセツ',
      };
      PayrollStatementRecord record(Map<String, dynamic> values) =>
          PayrollStatementRecord(
            id: 'adopted-v4',
            companyName: 'すみだ建設株式会社',
            workerName: '斉藤 隆一',
            periodStart: DateTime(2026, 10, 1),
            periodEnd: DateTime(2026, 10, 31),
            issuedAt: DateTime(2026, 10, 25),
            grossPay: 408248,
            deductions: 95600,
            netPay: 312648,
            detail: values,
          );
      final original = jsonEncode(detail);
      final pdf = await PayrollPdfService.buildPdf(
        record(detail),
        regularFont: font,
        boldFont: font,
      );
      final contents = latin1.decode(pdf);
      expect(contents, startsWith('%PDF-'));
      expect(RegExp(r'/Type\s*/Page\b').allMatches(contents), hasLength(1));
      expect(
        jsonEncode(detail),
        original,
        reason: 'PDF rendering must not mutate stored detail or bank data.',
      );
      expect(
        PayrollPdfService.buildTextSnapshot(record(detail)),
        contains('¥312,648'),
      );
      if (outputDirectory != null) {
        await Directory(outputDirectory).create(recursive: true);
        await File('$outputDirectory/payroll_flutter_v4.pdf').writeAsBytes(pdf);
      }
      final verificationOutput =
          outputDirectory ??
          (await Directory.systemTemp.createTemp('sko-payroll-pdf-')).path;
      await Directory(verificationOutput).create(recursive: true);
      for (final mode in <String, String>{
        'monthly': '月給',
        'hourly': '時給',
        'daily': '日給',
      }.entries) {
        final modeDetail = {
          ...detail,
          'pay_type': mode.key == 'monthly' ? '' : mode.key,
          '給与方式': mode.value,
        };
        final modePdf = await PayrollPdfService.buildPdf(
          record(modeDetail),
          regularFont: font,
          boldFont: font,
        );
        final modeFile = File(
          '$verificationOutput/payroll_flutter_${mode.key}.pdf',
        );
        await modeFile.writeAsBytes(modePdf);
        final extracted = await _inspectPayrollPdf(modeFile);
        final pages = extracted['pages'] as List<dynamic>;
        expect(pages, hasLength(1));
        final page = pages.single as Map<String, dynamic>;
        expect(page['width'], closeTo(595.2756, .01));
        expect(page['height'], closeTo(841.8898, .01));
        final spans = (page['spans'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        final banner = spans.where((span) {
          final box = (span['bbox'] as List<dynamic>).cast<num>();
          return box[1] >= 97 && box[1] < 125 && box[0] < 270;
        }).toList();
        final label = banner.singleWhere(
          (span) =>
              (span['text'] as String).replaceAll(RegExp(r'\s+'), '') ==
              mode.value,
        );
        final labelBox = (label['bbox'] as List<dynamic>).cast<num>();
        expect(labelBox[0], closeTo(50, .1));
        expect(
          labelBox[3],
          lessThanOrEqualTo(125.1),
          reason: 'Pay type must remain inside the adopted blue banner.',
        );
        final expectedExplanation = mode.key == 'monthly'
            ? '月固定給'
            : mode.key == 'hourly'
            ? '勤務時間'
            : '勤務日数';
        final explanation = banner.singleWhere(
          (span) => (span['text'] as String).contains(expectedExplanation),
        );
        final explanationBox = (explanation['bbox'] as List<dynamic>)
            .cast<num>();
        expect(
          explanationBox[0],
          closeTo(138, .1),
          reason:
              'Adjacent explanation must not move when the pay type changes.',
        );
        expect(
          explanationBox[2],
          lessThanOrEqualTo(256.1),
          reason: 'The explanation must fit without clipping or overlapping.',
        );
        expect(explanationBox[3], lessThanOrEqualTo(125.1));
        final normalizedText = (page['text'] as String).replaceAll(
          RegExp(r'\s+'),
          '',
        );
        expect(normalizedText, contains(mode.value));
        expect(
          RegExp(r'(?<![0-9.])0(?:\.0)?(?:日|時間|円)').hasMatch(normalizedText),
          isFalse,
          reason:
              'Zero work metrics and amounts must be blank in the actual PDF.',
        );
      }
      final many = {
        ...detail,
        'custom_earnings': [
          for (var i = 0; i < 31; i++)
            {'name': '登録手当${i + 1}', 'amount_yen': (i + 1) * 100},
        ],
      };
      final continued = await PayrollPdfService.buildPdf(
        record(many),
        regularFont: font,
        boldFont: font,
      );
      expect(
        RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(continued)),
        hasLength(3),
        reason: 'More than fifteen rows must continue on readable A4 pages.',
      );
      final zeroItems = {
        ...detail,
        'custom_earnings': [
          for (var i = 0; i < 31; i++)
            {'name': '未支給項目${i + 1}', 'amount_yen': 0},
        ],
        'custom_deductions': [
          for (var i = 0; i < 31; i++)
            {'name': '未控除項目${i + 1}', 'amount_yen': 0},
        ],
      };
      final zeroPdf = await PayrollPdfService.buildPdf(
        PayrollStatementRecord(
          id: 'zero-amounts',
          companyName: '登録会社',
          workerName: '登録社員',
          periodStart: DateTime(2026, 10, 1),
          periodEnd: DateTime(2026, 10, 31),
          grossPay: 0,
          deductions: 0,
          netPay: 0,
          detail: zeroItems,
        ),
        regularFont: font,
        boldFont: font,
      );
      expect(
        RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(zeroPdf)),
        hasLength(1),
        reason: 'Zero-value registered items must not produce extra pages.',
      );
      final zeroFile = File(
        '$verificationOutput/payroll_flutter_zero_amounts.pdf',
      );
      await zeroFile.writeAsBytes(zeroPdf);
      final zeroReport = await _inspectPayrollPdf(zeroFile);
      final zeroPage =
          (zeroReport['pages'] as List<dynamic>).single as Map<String, dynamic>;
      final shortCompanySpans = (zeroPage['spans'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final shortTagline = shortCompanySpans.singleWhere(
        (span) => (span['text'] as String)
            .replaceAll(RegExp(r'\s+'), '')
            .contains('人と現場をつなぐ未来をつくる'),
      );
      final shortTaglineBox = (shortTagline['bbox'] as List<dynamic>)
          .cast<num>();
      final sealBoxes = (zeroPage['seals'] as List<dynamic>)
          .cast<List<dynamic>>();
      expect(sealBoxes, isNotEmpty);
      for (final sealBox in sealBoxes) {
        final coordinates = sealBox.cast<num>();
        expect(
          shortTaglineBox[1],
          greaterThanOrEqualTo(coordinates[3] + .5),
          reason: 'The readable short-company tagline must sit below the seal.',
        );
      }
      expect(
        shortTaglineBox[3],
        lessThan(97),
        reason: 'The tagline must stay above the adopted blue pay-type banner.',
      );
      expect(
        shortTagline['size'] as num,
        greaterThanOrEqualTo(5.4),
        reason: 'Short company names must not shrink the tagline into unreadable text.',
      );
      final zeroText = (zeroPage['text'] as String).replaceAll(
        RegExp(r'\s+'),
        '',
      );
      expect(zeroText, isNot(contains('未支給項目')));
      expect(zeroText, isNot(contains('未控除項目')));
      expect(
        RegExp(r'(?<![0-9.])0(?:\.0)?(?:日|時間|円)').hasMatch(zeroText),
        isFalse,
      );
      if (outputDirectory != null) {
        await File('$outputDirectory/payroll_flutter_many_rows.pdf')
            .writeAsBytes(continued);
      }
    },
    skip: !hasFont
        ? 'Set SKO_PDF_FONT_PATH to a local Japanese TTF for real PDF rendering.'
        : false,
  );
}

Future<Map<String, dynamic>> _inspectPayrollPdf(File file) async {
  final result = await Process.run('python', [
    '-c',
    r'''import fitz,json,sys
pdf=fitz.open(sys.argv[1])
print(json.dumps({'pages':[{'width':p.rect.width,'height':p.rect.height,'text':p.get_text(),'seals':[list(d['rect']) for d in p.get_drawings() if d['color'] and d['color'][0]>.9 and d['color'][1]<.2 and d['color'][2]<.2 and d['rect'].width>25 and d['rect'].height>25],'spans':[{'text':s['text'],'bbox':s['bbox'],'size':s['size']} for b in p.get_text('dict')['blocks'] for l in b.get('lines',[]) for s in l['spans']]} for p in pdf]},ensure_ascii=False))''',
    file.path,
  ]);
  expect(result.exitCode, 0, reason: result.stderr.toString());
  return jsonDecode(result.stdout.toString()) as Map<String, dynamic>;
}
