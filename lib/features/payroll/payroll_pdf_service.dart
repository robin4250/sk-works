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

    document.addPage(
      pw.Page(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(18 * PdfPageFormat.mm),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              '給 与 明 細',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 18),
            pw.Text(statement.companyName, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Text(statement.workerName),
            pw.Text('対象期間：${_date(statement.periodStart)} ～ ${_date(statement.periodEnd)}'),
            pw.SizedBox(height: 14),
            pw.Divider(),
            _moneyRow('総支給額', statement.grossPay),
            _moneyRow('控除額', statement.deductions),
            pw.Divider(),
            _moneyRow('差引支給額', statement.netPay, strong: true),
            if (statement.detail.isNotEmpty) ...[
              pw.SizedBox(height: 18),
              pw.Text('内訳', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              for (final entry in statement.detail.entries)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(entry.key),
                    pw.Text(entry.value.toString()),
                  ],
                ),
            ],
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
      '${statement.monthLabel}\n総支給額 ${_yen(statement.grossPay)}\n'
      '控除額 ${_yen(statement.deductions)}\n差引支給額 ${_yen(statement.netPay)}';

  static pw.Widget _moneyRow(String label, int value, {bool strong = false}) {
    final style = pw.TextStyle(
      fontSize: strong ? 15 : 11,
      fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [pw.Text(label, style: style), pw.Text(_yen(value), style: style)],
      ),
    );
  }

  static String _date(DateTime value) =>
      '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}';

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
