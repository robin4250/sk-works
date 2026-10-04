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

    final detailEntries = statement.detail.entries.toList();

    document.addPage(
      pw.Page(
        pageFormat: format,
        margin: const pw.EdgeInsets.fromLTRB(
          14 * PdfPageFormat.mm,
          13 * PdfPageFormat.mm,
          14 * PdfPageFormat.mm,
          13 * PdfPageFormat.mm,
        ),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              '給与明細書',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: 21,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            pw.SizedBox(height: 7),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  flex: 3,
                  child: _boxedInfo(
                    [
                      ('会社名', statement.companyName),
                      ('氏名', statement.workerName),
                    ],
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  flex: 2,
                  child: _boxedInfo(
                    [
                      ('対象', statement.monthLabel),
                      (
                        '支払日',
                        statement.issuedAt == null
                            ? ''
                            : _date(statement.issuedAt!),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 9),
            pw.Row(
              children: [
                pw.Expanded(
                  child: _summaryBox('総支給額', statement.grossPay),
                ),
                pw.SizedBox(width: 5),
                pw.Expanded(
                  child: _summaryBox('総控除額', statement.deductions),
                ),
                pw.SizedBox(width: 5),
                pw.Expanded(
                  child: _summaryBox(
                    '差引支給額',
                    statement.netPay,
                    strong: true,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 11),
            pw.Text(
              '支給・控除内訳',
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Table(
              border: pw.TableBorder.all(
                color: PdfColors.blueGrey500,
                width: 0.6,
              ),
              columnWidths: const {
                0: pw.FlexColumnWidth(2.5),
                1: pw.FlexColumnWidth(1.5),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.blueGrey100,
                  ),
                  children: [
                    _cell('項目', bold: true),
                    _cell('金額・内容', bold: true, right: true),
                  ],
                ),
                if (detailEntries.isEmpty)
                  pw.TableRow(
                    children: [
                      _cell('内訳'),
                      _cell('設定未入力', right: true),
                    ],
                  )
                else
                  for (final entry in detailEntries)
                    pw.TableRow(
                      children: [
                        _cell(entry.key),
                        _cell(_detailValue(entry.value), right: true),
                      ],
                    ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(
                color: PdfColors.blueGrey500,
                width: 0.6,
              ),
              columnWidths: const {
                0: pw.FlexColumnWidth(2),
                1: pw.FlexColumnWidth(1),
              },
              children: [
                pw.TableRow(
                  children: [
                    _cell('総支給額', bold: true),
                    _cell(_yen(statement.grossPay), bold: true, right: true),
                  ],
                ),
                pw.TableRow(
                  children: [
                    _cell('総控除額', bold: true),
                    _cell(_yen(statement.deductions), bold: true, right: true),
                  ],
                ),
                pw.TableRow(
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.blueGrey50,
                  ),
                  children: [
                    _cell('差引支給額', bold: true),
                    _cell(
                      _yen(statement.netPay),
                      bold: true,
                      right: true,
                      fontSize: 12,
                    ),
                  ],
                ),
              ],
            ),
            pw.Spacer(),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                statement.reviewConfirmed ? '確認済み' : '未確定',
                style: pw.TextStyle(
                  fontSize: 8.5,
                  color: statement.reviewConfirmed
                      ? PdfColors.green700
                      : PdfColors.red700,
                ),
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              '上記のとおり給与を支給します。',
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 9),
            ),
          ],
        ),
      ),
    );
    return document.save();
  }

  static Future<bool> printStatement(PayrollStatementRecord statement) {
    return Printing.layoutPdf(
      name: '${statement.monthLabel}_${statement.workerName}_給与明細.pdf',
      format: PdfPageFormat.a4,
      onLayout: (format) => buildPdf(statement, format: format),
    );
  }

  static String buildTextSnapshot(PayrollStatementRecord statement) =>
      '給与明細\n${statement.companyName}\n${statement.workerName}\n'
      '${statement.monthLabel}\n${statement.reviewConfirmed ? '確認済み' : '未確定'}\n'
      '総支給額 ${_yen(statement.grossPay)}\n'
      '控除額 ${_yen(statement.deductions)}\n差引支給額 ${_yen(statement.netPay)}';

  static pw.Widget _boxedInfo(List<(String, String)> rows) {
    return pw.Table(
      border: pw.TableBorder.all(
        color: PdfColors.blueGrey400,
        width: 0.55,
      ),
      columnWidths: const {
        0: pw.FlexColumnWidth(1),
        1: pw.FlexColumnWidth(2.5),
      },
      children: [
        for (final row in rows)
          pw.TableRow(
            children: [
              _cell(row.$1, bold: true, background: PdfColors.blueGrey50),
              _cell(row.$2),
            ],
          ),
      ],
    );
  }

  static pw.Widget _summaryBox(
    String label,
    int value, {
    bool strong = false,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(
          color: PdfColors.blueGrey500,
          width: strong ? 1.0 : 0.6,
        ),
        color: strong ? PdfColors.blueGrey50 : PdfColors.white,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              _yen(value),
              style: pw.TextStyle(
                fontSize: strong ? 15 : 13,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _cell(
    String text, {
    bool bold = false,
    bool right = false,
    double fontSize = 9,
    PdfColor? background,
  }) {
    final child = pw.Container(
      color: background,
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(
        text,
        textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
        style: pw.TextStyle(
          fontSize: fontSize,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
    return child;
  }

  static String _date(DateTime value) =>
      '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}';

  static String _detailValue(Object? value) {
    if (value is num) return _yen(value.toInt());
    return value?.toString() ?? '';
  }

  static String _yen(int value) {
    final negative = value < 0;
    final digits = value.abs().toString();
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return '${negative ? '-' : ''}¥$out';
  }
}
