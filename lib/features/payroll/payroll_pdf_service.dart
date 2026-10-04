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
    final attendance = _pick(detail, const [
      '出勤日数',
      '休日出勤',
      '残業時間',
      '法定外出時間',
      '早出時間',
      '夜間時間',
    ]);

    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(
          8 * PdfPageFormat.mm,
          8 * PdfPageFormat.mm,
          8 * PdfPageFormat.mm,
          8 * PdfPageFormat.mm,
        ),
        build: (_) => _sheet(
          statement,
          attendance: attendance,
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
    required Map<String, Object?> attendance,
    required Map<String, Object?> earnings,
    required Map<String, Object?> deductions,
  }) {
    final blue = PdfColor.fromHex('#D9E6F6');
    final border = PdfColor.fromHex('#6A88A8');

    String value(Map<String, Object?> source, String key) {
      final raw = source[key];
      if (raw == null) return '';
      if (raw is num) return _number(raw.toInt());
      return raw.toString();
    }

    const earningLabels = [
      '基本給',
      '残業手当',
      '勤続手当',
      '役職手当',
      '家族手当',
      '働き方手当',
      '交通費',
      'その他',
      '',
      '',
    ];
    const deductionLabels = [
      '健康保険料',
      '介護保険料',
      '厚生年金保険',
      '雇用保険料',
      '所得税',
      '住民税',
      'SKB会費',
      '道具代',
      'その他',
      '',
    ];

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              flex: 6,
              child: pw.Column(
                children: [
                  pw.Text(
                    '給与明細書',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 5),
                  pw.Table(
                    border: pw.TableBorder.all(color: border, width: .55),
                    columnWidths: const {
                      0: pw.FlexColumnWidth(2.2),
                      1: pw.FlexColumnWidth(1.2),
                      2: pw.FlexColumnWidth(3),
                    },
                    children: [
                      pw.TableRow(
                        decoration: pw.BoxDecoration(color: blue),
                        children: [
                          _cell('所属', center: true, bold: true),
                          _cell('社員番号', center: true, bold: true),
                          _cell('氏名', center: true, bold: true),
                        ],
                      ),
                      pw.TableRow(
                        children: [
                          _cell(statement.companyName),
                          _cell('', center: true),
                          _cell('${statement.workerName}　様'),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 16),
            pw.SizedBox(
              width: 155,
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
        pw.SizedBox(height: 7),
        _sectionGrid(
          title: '勤怠',
          labels: const [
            '出勤日数',
            '休日出勤',
            '残業時間',
            '法定外出時間',
            '',
            '',
            '',
            '',
            '',
            '',
          ],
          values: [
            value(attendance, '出勤日数'),
            value(attendance, '休日出勤'),
            value(attendance, '残業時間'),
            value(attendance, '法定外出時間'),
            '',
            '',
            '',
            '',
            '',
            '',
          ],
          blue: blue,
          border: border,
          blankRows: 1,
        ),
        pw.SizedBox(height: 7),
        _sectionGrid(
          title: '支給',
          labels: earningLabels,
          values: [
            for (final label in earningLabels)
              if (label == 'その他')
                _otherAmount(earnings, earningLabels)
              else if (label.isEmpty)
                ''
              else
                value(earnings, label),
          ],
          blue: blue,
          border: border,
          blankRows: 3,
        ),
        pw.SizedBox(height: 7),
        _sectionGrid(
          title: '控除',
          labels: deductionLabels,
          values: [
            for (final label in deductionLabels)
              if (label == 'その他')
                _otherAmount(deductions, deductionLabels)
              else if (label.isEmpty)
                ''
              else
                value(deductions, label),
          ],
          blue: blue,
          border: border,
          blankRows: 3,
        ),
        pw.SizedBox(height: 7),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.SizedBox(
            width: 310,
            child: pw.Table(
              border: pw.TableBorder.all(color: border, width: .55),
              children: [
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: blue),
                  children: [
                    _cell('総支給額', center: true, bold: true),
                    _cell('総控除額', center: true, bold: true),
                    _cell('差引支給額', center: true, bold: true),
                  ],
                ),
                pw.TableRow(
                  children: [
                    _cell(_number(statement.grossPay), right: true),
                    _cell(_number(statement.deductions), right: true),
                    _cell(_number(statement.netPay), right: true, bold: true),
                  ],
                ),
              ],
            ),
          ),
        ),
        pw.SizedBox(height: 7),
        pw.Table(
          border: pw.TableBorder.all(color: border, width: .55),
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: blue),
              children: [
                _cell('日給単価', center: true, bold: true),
                _cell(''),
                _cell(''),
                _cell(''),
                _cell(''),
                _cell('月次減税額', center: true, bold: true, fontSize: 6.5),
                _cell('減税前未済額', center: true, bold: true, fontSize: 6.5),
                _cell('減税前所得税', center: true, bold: true, fontSize: 6.5),
                _cell('定額減税額', center: true, bold: true, fontSize: 6.5),
                _cell('定額減税未済', center: true, bold: true, fontSize: 6.5),
              ],
            ),
            pw.TableRow(
              children: [
                _cell(_detail(statement.detail, '日給単価'), right: true),
                for (var i = 0; i < 4; i++) _cell(''),
                _cell(_detail(statement.detail, '月次減税額'), right: true),
                _cell(_detail(statement.detail, '減税前未済額'), right: true),
                _cell(_detail(statement.detail, '減税前所得税'), right: true),
                _cell(_detail(statement.detail, '定額減税額'), right: true),
                _cell(_detail(statement.detail, '定額減税未済'), right: true),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 5),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('お疲れさまです。', style: const pw.TextStyle(fontSize: 7.5)),
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

  static pw.Widget _sectionGrid({
    required String title,
    required List<String> labels,
    required List<String> values,
    required PdfColor blue,
    required PdfColor border,
    required int blankRows,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          width: 28,
          decoration: pw.BoxDecoration(
            color: blue,
            border: pw.Border.all(color: border, width: .55),
          ),
          alignment: pw.Alignment.center,
          child: pw.Text(
            title.split('').join('\n'),
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.Expanded(
          child: pw.Table(
            border: pw.TableBorder.all(color: border, width: .55),
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: blue),
                children: [
                  for (final label in labels)
                    _cell(label, center: true, bold: true, fontSize: 7),
                ],
              ),
              pw.TableRow(
                children: [
                  for (final item in values)
                    _cell(item, right: true, fontSize: 7.5),
                ],
              ),
              for (var row = 0; row < blankRows; row++)
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
    for (final entry in detail.entries) {
      final key = entry.key.trim();
      if (keys.contains(key)) result[key] = entry.value;
    }
    if (keys.contains('出勤に基づく支給額') &&
        !result.containsKey('基本給') &&
        detail['出勤に基づく支給額'] != null) {
      result['基本給'] = detail['出勤に基づく支給額'];
    }
    return result;
  }

  static String _otherAmount(
    Map<String, Object?> source,
    List<String> known,
  ) {
    var total = 0;
    for (final entry in source.entries) {
      if (known.contains(entry.key)) continue;
      if (entry.value is num) total += (entry.value as num).toInt();
    }
    return total == 0 ? '' : _number(total);
  }

  static String _detail(Map<String, dynamic> detail, String key) {
    final raw = detail[key];
    if (raw == null) return '';
    if (raw is num) return _number(raw.toInt());
    return raw.toString();
  }

  static pw.Widget _cell(
    String text, {
    bool bold = false,
    bool right = false,
    bool center = false,
    double fontSize = 7.5,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2.6),
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
