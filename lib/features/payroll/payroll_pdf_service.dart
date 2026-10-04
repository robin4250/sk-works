import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'payroll_statement_repository.dart';

class PayrollPdfService {
  const PayrollPdfService._();

  static Future<Uint8List> buildPdf(
    PayrollStatementRecord statement, {
    PdfPageFormat format = PdfPageFormat.a4,
  }) async {
    final regular = await PdfGoogleFonts.notoSansJPRegular();
    final bold = await PdfGoogleFonts.notoSansJPBold();
    final document = pw.Document(
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );

    final detail = statement.detail;
    final earnings = _pick(detail, const [
      '基本給',
      '残業手当',
      '勤続手当',
      '役職手当',
      '家族手当',
      '働き方手当',
      '交通費',
      '出勤に基づく支給額',
    ]);
    final deductions = _pick(detail, const [
      '健康保険料',
      '介護保険料',
      '厚生年金保険',
      '雇用保険料',
      '所得税',
      '住民税',
      'SKB会費',
      '道具代',
      '社会保険',
      'その他控除',
    ]);

    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(8 * PdfPageFormat.mm),
        build: (_) => _sheet(
          statement,
          detail: detail,
          earnings: earnings,
          deductions: deductions,
        ),
      ),
    );
    return document.save();
  }

  static Future<bool> printStatement(PayrollStatementRecord statement) {
    return Printing.layoutPdf(
      name: '${statement.monthLabel}_${statement.workerName}_給与明細.pdf',
      format: PdfPageFormat.a4.landscape,
      onLayout: (_) => buildPdf(statement),
    );
  }

  static String buildTextSnapshot(PayrollStatementRecord statement) =>
      '給与明細書\n${statement.companyName}\n${statement.workerName}\n'
      '${statement.monthLabel}\n${statement.reviewConfirmed ? '確認済み' : '未確定'}\n'
      '総支給額 ${_yen(statement.grossPay)}\n'
      '総控除額 ${_yen(statement.deductions)}\n'
      '差引支給額 ${_yen(statement.netPay)}';

  static pw.Widget _sheet(
    PayrollStatementRecord statement, {
    required Map<String, dynamic> detail,
    required Map<String, Object?> earnings,
    required Map<String, Object?> deductions,
  }) {
    final headerFill = PdfColor.fromHex('#DCE8F6');
    final grid = PdfColor.fromHex('#6D89A8');
    // Supplied payroll form: 勤怠 / 支給 / 控除 are separate roomy grids.
    const referenceLayout = '勤怠・支給・控除';
    assert(referenceLayout.isNotEmpty);

    final earningLabels = <String>[
      '基本給',
      '残業手当',
      '勤続手当',
      '役職手当',
      '家族手当',
      '働き方手当',
      '',
      '',
      '',
      '',
    ];
    final deductionLabels = <String>[
      '健康保険料',
      '介護保険料',
      '厚生年金保険',
      '雇用保険料',
      '所得税',
      '住民税',
      'SKB会費',
      '道具代',
      '',
      '',
    ];

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                children: [
                  pw.Text(
                    '給与明細書',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Table(
                    border: pw.TableBorder.all(color: grid, width: .55),
                    columnWidths: const {
                      0: pw.FlexColumnWidth(2.2),
                      1: pw.FlexColumnWidth(1.2),
                      2: pw.FlexColumnWidth(3),
                    },
                    children: [
                      pw.TableRow(
                        decoration: pw.BoxDecoration(color: headerFill),
                        children: [
                          _cell('所属', center: true, bold: true),
                          _cell('社員番号', center: true, bold: true),
                          _cell('氏名', center: true, bold: true),
                        ],
                      ),
                      pw.TableRow(
                        children: [
                          _cell(statement.companyName),
                          _cell(_text(detail, '社員番号'), center: true),
                          _cell('${statement.workerName}　様'),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 18),
            pw.SizedBox(
              width: 160,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.SizedBox(height: 8),
                  pw.Text(
                    '${statement.periodEnd.year}年${statement.periodEnd.month}月分',
                    style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    '支払日　${statement.issuedAt == null ? '' : _date(statement.issuedAt!)}',
                    style: const pw.TextStyle(fontSize: 8.5),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    statement.companyName,
                    style: pw.TextStyle(
                      fontSize: 9.5,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 9),
        _section(
          title: '勤怠',
          labels: const [
            '出勤日数',
            '休出日数',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
          ],
          values: [
            _text(detail, '出勤日数'),
            _textAny(detail, const ['休出日数', '休日出勤']),
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
          ],
          secondLabels: const [
            '残業時間',
            '法定休出時間',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
          ],
          secondValues: [
            _text(detail, '残業時間'),
            _textAny(detail, const ['法定休出時間', '法定外出時間']),
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
          ],
          headerFill: headerFill,
          grid: grid,
          extraBlankRows: 0,
        ),
        pw.SizedBox(height: 9),
        _section(
          title: '支給',
          labels: earningLabels,
          values: [
            _amount(earnings, '基本給', fallbackKey: '出勤に基づく支給額'),
            _amount(earnings, '残業手当'),
            _amount(earnings, '勤続手当'),
            _amount(earnings, '役職手当'),
            _amount(earnings, '家族手当'),
            _amount(earnings, '働き方手当'),
            '',
            '',
            '',
            '',
          ],
          secondLabels: const ['', '', '', '', '', '', '', '', '', ''],
          secondValues: const ['', '', '', '', '', '', '', '', '', ''],
          headerFill: headerFill,
          grid: grid,
          extraBlankRows: 3,
        ),
        pw.SizedBox(height: 9),
        _section(
          title: '控除',
          labels: deductionLabels,
          values: [
            _amount(deductions, '健康保険料', fallbackKey: '社会保険'),
            _amount(deductions, '介護保険料'),
            _amount(deductions, '厚生年金保険'),
            _amount(deductions, '雇用保険料'),
            _amount(deductions, '所得税'),
            _amount(deductions, '住民税'),
            _amount(deductions, 'SKB会費'),
            _amount(deductions, '道具代'),
            '',
            '',
          ],
          secondLabels: const ['', '', '', '', '', '', '', '', '', ''],
          secondValues: const ['', '', '', '', '', '', '', '', '', ''],
          headerFill: headerFill,
          grid: grid,
          extraBlankRows: 3,
        ),
        pw.SizedBox(height: 9),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.SizedBox(
            width: 315,
            child: pw.Table(
              border: pw.TableBorder.all(color: grid, width: .55),
              children: [
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: headerFill),
                  children: [
                    _cell('総支給額', center: true, bold: true),
                    _cell('総控除額', center: true, bold: true),
                    _cell('差引支給額', center: true, bold: true),
                  ],
                ),
                pw.TableRow(
                  children: [
                    _cell(_number(statement.grossPay), right: true, bold: true),
                    _cell(_number(statement.deductions), right: true, bold: true),
                    _cell(_number(statement.netPay), right: true, bold: true),
                  ],
                ),
              ],
            ),
          ),
        ),
        pw.SizedBox(height: 9),
        pw.Table(
          border: pw.TableBorder.all(color: grid, width: .55),
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: headerFill),
              children: [
                _cell('日給単価', center: true, bold: true),
                _cell(''),
                _cell(''),
                _cell(''),
                _cell(''),
                _cell('月次減税額', center: true, bold: true, fontSize: 6.4),
                _cell('減税前未済額', center: true, bold: true, fontSize: 6.4),
                _cell('減税前所得税', center: true, bold: true, fontSize: 6.4),
                _cell('定額減税額', center: true, bold: true, fontSize: 6.4),
                _cell('定額減税未済', center: true, bold: true, fontSize: 6.4),
              ],
            ),
            pw.TableRow(
              children: [
                _cell(_text(detail, '日給単価'), right: true),
                _cell(''),
                _cell(''),
                _cell(''),
                _cell(''),
                _cell(_text(detail, '月次減税額'), right: true),
                _cell(_text(detail, '減税前未済額'), right: true),
                _cell(_text(detail, '減税前所得税'), right: true),
                _cell(_text(detail, '定額減税額'), right: true),
                _cell(_text(detail, '定額減税未済'), right: true),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 5),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('お疲れさまです。', style: const pw.TextStyle(fontSize: 8)),
            pw.Text(
              statement.reviewConfirmed ? '確認済み' : '未確定',
              style: pw.TextStyle(
                fontSize: 7.5,
                color: statement.reviewConfirmed
                    ? PdfColors.green700
                    : PdfColors.red700,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _section({
    required String title,
    required List<String> labels,
    required List<String> values,
    required List<String> secondLabels,
    required List<String> secondValues,
    required PdfColor headerFill,
    required PdfColor grid,
    required int extraBlankRows,
  }) {
    return pw.Row(
      children: [
        pw.Container(
          width: 30,
          padding: const pw.EdgeInsets.symmetric(vertical: 6),
          decoration: pw.BoxDecoration(
            color: headerFill,
            border: pw.Border.all(color: grid, width: .55),
          ),
          alignment: pw.Alignment.center,
          child: pw.Text(
            title.split('').join('\n'),
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.Expanded(
          child: pw.Table(
            border: pw.TableBorder.all(color: grid, width: .55),
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: headerFill),
                children: [
                  for (final label in labels)
                    _cell(label, center: true, bold: true, fontSize: 7),
                ],
              ),
              pw.TableRow(
                children: [
                  for (final value in values)
                    _cell(value, right: true, fontSize: 8),
                ],
              ),
              if (secondLabels.any((value) => value.isNotEmpty))
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: headerFill),
                  children: [
                    for (final label in secondLabels)
                      _cell(label, center: true, bold: true, fontSize: 7),
                  ],
                ),
              if (secondLabels.any((value) => value.isNotEmpty))
                pw.TableRow(
                  children: [
                    for (final value in secondValues)
                      _cell(value, right: true, fontSize: 8),
                  ],
                ),
              for (var row = 0; row < extraBlankRows; row++)
                pw.TableRow(
                  children: [
                    for (var i = 0; i < labels.length; i++) _cell(''),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  static Map<String, Object?> _pick(
    Map<String, dynamic> detail,
    List<String> keys,
  ) {
    final result = <String, Object?>{};
    for (final key in keys) {
      if (detail.containsKey(key)) result[key] = detail[key];
    }
    return result;
  }

  static String _amount(
    Map<String, Object?> source,
    String key, {
    String? fallbackKey,
  }) {
    final value = source[key] ?? (fallbackKey == null ? null : source[fallbackKey]);
    if (value is num) return _number(value.toInt());
    return value?.toString() ?? '';
  }

  static String _textAny(
    Map<String, dynamic> source,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = source[key];
      if (value == null) continue;
      if (value is num) return _number(value.toInt());
      final text = value.toString();
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  static String _text(Map<String, dynamic> source, String key) {
    final value = source[key];
    if (value is num) return _number(value.toInt());
    return value?.toString() ?? '';
  }

  static pw.Widget _cell(
    String text, {
    bool bold = false,
    bool right = false,
    bool center = false,
    double fontSize = 7.5,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      child: pw.Container(
        height: 18,
        alignment: right
            ? pw.Alignment.centerRight
            : center
                ? pw.Alignment.center
                : pw.Alignment.centerLeft,
        child: pw.Text(
        text,
        textAlign: right
            ? pw.TextAlign.right
            : center
                ? pw.TextAlign.center
                : pw.TextAlign.left,
        style: pw.TextStyle(
          fontSize: fontSize,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
        ),
      ),
    );
  }

  static String _date(DateTime value) =>
      '${value.year}年${value.month}月${value.day}日';

  static String _number(int value) {
    final negative = value < 0;
    final digits = value.abs().toString();
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return '${negative ? '-' : ''}$out';
  }

  static String _yen(int value) => '¥${_number(value)}';
}
