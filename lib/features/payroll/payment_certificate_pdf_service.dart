import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'payment_certificate_repository.dart';

class PaymentCertificatePdfService {
  const PaymentCertificatePdfService._();

  static Future<Uint8List> buildPdf(
    PaymentCertificateRecord record, {
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
              '工事代金支払明細書',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              '${record.partnerCompanyName} 御中',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              '下記の通りお支払いたします。',
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(
                color: PdfColors.blueGrey500,
                width: 0.6,
              ),
              columnWidths: const {
                0: pw.FlexColumnWidth(2.6),
                1: pw.FlexColumnWidth(1.2),
                2: pw.FlexColumnWidth(1.4),
                3: pw.FlexColumnWidth(1.5),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.blueGrey100,
                  ),
                  children: [
                    _cell('工事項目', bold: true),
                    _cell('数量', bold: true, right: true),
                    _cell('単価', bold: true, right: true),
                    _cell('支払金額', bold: true, right: true),
                  ],
                ),
                pw.TableRow(
                  children: [
                    _cell('工事代金'),
                    _cell('1', right: true),
                    _cell(_yen(record.netAmount), right: true),
                    _cell(_yen(record.netAmount), right: true),
                  ],
                ),
                for (var i = 0; i < 7; i++)
                  pw.TableRow(
                    children: [
                      _cell(''),
                      _cell(''),
                      _cell(''),
                      _cell(''),
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
                0: pw.FlexColumnWidth(2.6),
                1: pw.FlexColumnWidth(1.5),
              },
              children: [
                pw.TableRow(
                  children: [
                    _cell('合計', bold: true),
                    _cell(_yen(record.netAmount), bold: true, right: true),
                  ],
                ),
                pw.TableRow(
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.blueGrey50,
                  ),
                  children: [
                    _cell('差引残高', bold: true),
                    _cell(
                      _yen(record.netAmount),
                      bold: true,
                      right: true,
                      fontSize: 12,
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 12),
            _infoRow(
              '対象期間',
              '${_date(record.periodStart)} ～ ${_date(record.periodEnd)}',
            ),
            _infoRow('状態', record.status == 'draft' ? '下書き' : '確定'),
            _infoRow('改訂', '第${record.revision}版'),
            pw.Spacer(),
            pw.Text(
              '支払内容の詳細設定が未入力の場合は、0円の下書きとして表示します。',
              style: const pw.TextStyle(
                fontSize: 8,
                color: PdfColors.grey700,
              ),
            ),
          ],
        ),
      ),
    );

    return document.save();
  }

  static Future<bool> printCertificate(PaymentCertificateRecord record) {
    return Printing.layoutPdf(
      name: '${record.monthLabel}_${record.partnerCompanyName}_支払証明書.pdf',
      format: PdfPageFormat.a4,
      onLayout: (format) => buildPdf(record, format: format),
    );
  }

  static pw.Widget _infoRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 65,
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: const pw.TextStyle(fontSize: 9),
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
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      child: pw.Text(
        text,
        textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
        style: pw.TextStyle(
          fontSize: fontSize,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
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
