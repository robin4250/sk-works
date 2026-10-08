import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'payment_certificate_repository.dart';
import '../shared/company_seal_pdf.dart';

class PaymentCertificatePdfService {
  const PaymentCertificatePdfService._();

  static Future<Uint8List> buildPdf(
    PaymentCertificateRecord record, {
    PdfPageFormat format = PdfPageFormat.a4,
    pw.Font? regularFont,
    pw.Font? boldFont,
  }) async {
    final regular = regularFont ?? await PdfGoogleFonts.notoSansJPRegular();
    final bold = boldFont ?? await PdfGoogleFonts.notoSansJPBold();
    final sealFont = await CompanySealPdf.loadFont();
    final document = pw.Document(
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );

    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(
          12 * PdfPageFormat.mm,
          10 * PdfPageFormat.mm,
          12 * PdfPageFormat.mm,
          10 * PdfPageFormat.mm,
        ),
        build: (_) => _sheet(record, sealFont, regular),
      ),
    );

    return document.save();
  }

  static Future<bool> printCertificate(PaymentCertificateRecord record) {
    return Printing.layoutPdf(
      name: '${record.monthLabel}_${record.partnerCompanyName}_支払証明書.pdf',
      format: PdfPageFormat.a4,
      onLayout: (_) => buildPdf(record),
    );
  }

  static pw.Widget _sheet(
    PaymentCertificateRecord record,
    pw.Font sealFont,
    pw.Font fallbackFont,
  ) {
    final lines = record.lines.isEmpty
        ? [
            PaymentCertificateLine(
              siteName: '工事代金',
              workContent: '',
              quantityLabel: '1',
              unitPriceYen: record.grossAmount,
              amountYen: record.grossAmount,
            ),
          ]
        : record.lines;

    final detailTotal = lines.fold<int>(0, (sum, line) => sum + line.amountYen);
    final gross = record.grossAmount != 0 ? record.grossAmount : detailTotal;
    final balance = gross - record.deductions;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'From:${record.payerCompanyName}',
              style: const pw.TextStyle(fontSize: 7),
            ),
            pw.Text(record.payerPhone, style: const pw.TextStyle(fontSize: 7)),
            pw.Text('P.001/001', style: const pw.TextStyle(fontSize: 7)),
          ],
        ),
        pw.SizedBox(height: 22),
        pw.Text(
          '工事代金支払明細書',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: 19,
            fontWeight: pw.FontWeight.bold,
            decoration: pw.TextDecoration.underline,
          ),
        ),
        pw.SizedBox(height: 16),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    record.monthLabel,
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                  pw.SizedBox(height: 9),
                  pw.Text(
                    '${record.partnerCompanyName}　御中',
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(
              width: 210,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (record.payerPostalCode.isNotEmpty)
                    pw.Text(
                      '〒${record.payerPostalCode}',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  if (record.payerAddress.isNotEmpty)
                    pw.Text(
                      record.payerAddress,
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  pw.Row(
                    mainAxisSize: pw.MainAxisSize.min,
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Flexible(
                        child: pw.Text(
                          record.payerCompanyName,
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                      pw.Transform.translate(
                        offset: const PdfPoint(-4, 0),
                        child: CompanySealPdf.build(
                          record.payerCompanyName,
                          size: 55,
                          font: sealFont,
                          fallbackFont: fallbackFont,
                        ),
                      ),
                    ],
                  ),
                  if (record.payerPhone.isNotEmpty)
                    pw.Text(
                      'TEL　${record.payerPhone}',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  if (record.payerFax.isNotEmpty)
                    pw.Text(
                      'FAX　${record.payerFax}',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 13),
        pw.Text('下記の通りお支払いいたします。', style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 3),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.black, width: .75),
          columnWidths: const {
            0: pw.FlexColumnWidth(2.5),
            1: pw.FlexColumnWidth(2.0),
            2: pw.FlexColumnWidth(.8),
            3: pw.FlexColumnWidth(1.0),
            4: pw.FlexColumnWidth(1.15),
          },
          children: [
            pw.TableRow(
              children: [
                _cell('作　業　所　名', center: true, bold: true),
                _cell('工　事　内　容', center: true, bold: true),
                _cell('数　量', center: true, bold: true),
                _cell('単　価', center: true, bold: true),
                _cell('支払金額', center: true, bold: true),
              ],
            ),
            for (final line in lines)
              pw.TableRow(
                children: [
                  _cell(line.siteName),
                  _cell(line.workContent),
                  _cell(_quantity(line.quantityLabel), right: true),
                  _cell(
                    line.unitPriceYen == 0
                        ? ''
                        : '${_number(line.unitPriceYen)}円',
                    right: true,
                  ),
                  _cell(_number(line.amountYen), right: true),
                ],
              ),
            pw.TableRow(
              children: [
                _cell(''),
                _cell('合　　計', right: true, bold: true),
                _cell(''),
                _cell(''),
                _cell(_number(gross), right: true, bold: true),
              ],
            ),
            if (record.deductions != 0)
              pw.TableRow(
                children: [
                  _cell(''),
                  _cell('控　　除', right: true),
                  _cell(''),
                  _cell(''),
                  _cell(_number(-record.deductions), right: true),
                ],
              ),
            pw.TableRow(
              children: [
                _cell(''),
                _cell('差　引　残　高', right: true, bold: true),
                _cell(''),
                _cell(''),
                _cell(
                  balance == 0 ? '' : '¥${_number(balance)}',
                  right: true,
                  bold: true,
                  fontSize: 10,
                ),
              ],
            ),
          ],
        ),
        pw.Spacer(),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              '対象期間：${_date(record.periodStart)} ～ ${_date(record.periodEnd)}',
              style: const pw.TextStyle(fontSize: 7),
            ),
            pw.Text(
              record.isPreview
                  ? 'プレビュー・出勤実績なし'
                  : record.status == 'draft'
                  ? '下書き・第${record.revision}版'
                  : '確定・第${record.revision}版',
              style: const pw.TextStyle(fontSize: 7),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _cell(
    String text, {
    bool bold = false,
    bool right = false,
    bool center = false,
    double fontSize = 8,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3.3),
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
      '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}';

  static String _number(int value) {
    if (value == 0) return '';
    final negative = value < 0;
    final digits = value.abs().toString();
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        out.write(',');
      }
      out.write(digits[i]);
    }
    return '${negative ? '-' : ''}$out';
  }

  static String _quantity(String value) {
    final trimmed = value.trim();
    // Only an entirely zero numeric quantity (with an optional known unit) is
    // blanked. Dates and descriptions containing a zero remain untouched.
    if (RegExp(r'^[+-]?0+(?:\.0+)?\s*(?:日|時間|回|人|人工)?$').hasMatch(trimmed))
      return '';
    return value;
  }
}
