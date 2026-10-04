import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../domain/invoice_engine.dart';

class InvoicePdfService {
  const InvoicePdfService._();

  static Future<Uint8List> buildPdf(
    List<InvoiceCalculationResult> invoices, {
    String? title,
    PdfPageFormat format = PdfPageFormat.a4,
  }) async {
    if (invoices.isEmpty) {
      throw ArgumentError.value(invoices, 'invoices', 'must not be empty');
    }

    final regular = await PdfGoogleFonts.notoSansJPRegular();
    final bold = await PdfGoogleFonts.notoSansJPBold();
    final theme = pw.ThemeData.withFont(base: regular, bold: bold);
    final document = pw.Document(theme: theme);

    for (final invoice in invoices) {
      document.addPage(
        pw.MultiPage(
          pageFormat: format,
          margin: const pw.EdgeInsets.all(14 * PdfPageFormat.mm),
          build: (_) => _invoiceWidgets(invoice),
        ),
      );
    }

    return document.save();
  }

  static Future<bool> printInvoices(
    List<InvoiceCalculationResult> invoices, {
    String? title,
  }) {
    final name = fileNameFor(invoices, title: title);
    return Printing.layoutPdf(
      name: name,
      format: PdfPageFormat.a4,
      onLayout: (format) => buildPdf(
        invoices,
        title: title,
        format: format,
      ),
    );
  }

  static Future<bool> shareInvoices(
    List<InvoiceCalculationResult> invoices, {
    String? title,
    String? subject,
    String? body,
  }) async {
    final bytes = await buildPdf(invoices, title: title);
    return Printing.sharePdf(
      bytes: bytes,
      filename: fileNameFor(invoices, title: title),
      subject: subject,
      body: body,
    );
  }

  static String fileNameFor(
    List<InvoiceCalculationResult> invoices, {
    String? title,
  }) {
    if (invoices.isEmpty) return '請求書.pdf';
    final base = title?.trim().isNotEmpty == true
        ? title!.trim()
        : invoices.length == 1
            ? '${invoices.first.customerId}_${invoices.first.billingPeriod}_請求書'
            : '請求書まとめ';
    final safe = base
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
    return '$safe.pdf';
  }

  static String buildTextSnapshot(
    List<InvoiceCalculationResult> invoices, {
    String? title,
  }) {
    final buffer = StringBuffer();
    if (title != null && title.trim().isNotEmpty) {
      buffer.writeln(title.trim());
    }

    for (final invoice in invoices) {
      buffer
        ..writeln('請求書')
        ..writeln(invoice.billingPeriod)
        ..writeln('${invoice.customerId} 御中');

      for (final site in invoice.siteCalculations) {
        buffer.writeln(site.siteName);
        for (final line in site.lines) {
          buffer.writeln(
            '${line.label} ${_quantity(line.quantity)} × '
            '${_yen(line.unitPriceYen)} = ${_yen(line.amountYen)}',
          );
        }
        if (site.manualAdjustmentYen != 0) {
          buffer.writeln('調整 ${_yen(site.manualAdjustmentYen)}');
        }
        if (site.welfareAmountYen != 0) {
          buffer.writeln('法定福利費 ${_yen(site.welfareAmountYen)}');
        }
      }

      buffer
        ..writeln('小計 ${_yen(invoice.subtotalYen)}')
        ..writeln('消費税 ${_yen(invoice.taxYen)}')
        ..writeln('請求合計 ${_yen(invoice.grandTotalYen)}');
    }

    return buffer.toString();
  }

  static List<pw.Widget> _invoiceWidgets(InvoiceCalculationResult invoice) {
    final rows = <List<String>>[];

    for (final site in invoice.siteCalculations) {
      if (site.lines.isEmpty) {
        rows.add([site.siteName, '', '', '']);
      } else {
        for (var index = 0; index < site.lines.length; index++) {
          final line = site.lines[index];
          rows.add([
            index == 0
                ? '${site.siteName}\n${line.label}'
                : line.label,
            _quantity(line.quantity),
            _yen(line.unitPriceYen),
            _yen(line.amountYen),
          ]);
        }
      }

      if (site.manualAdjustmentYen != 0) {
        rows.add([
          '${site.siteName} 調整',
          '',
          '',
          _yen(site.manualAdjustmentYen),
        ]);
      }

      if (site.welfareAmountYen != 0) {
        rows.add([
          '${site.siteName} 法定福利費',
          '',
          '',
          _yen(site.welfareAmountYen),
        ]);
      }
    }

    return [
      pw.Stack(
        children: [
          pw.Align(
            alignment: pw.Alignment.center,
            child: pw.Text(
              '御 請 求 書',
              style: pw.TextStyle(
                fontSize: 24,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Align(
            alignment: pw.Alignment.topRight,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(invoice.billingPeriod),
                pw.Text('請求書番号:'),
              ],
            ),
          ),
        ],
      ),
      pw.Divider(thickness: 1.5),
      pw.SizedBox(height: 18),
      pw.Text(
        '${invoice.customerId} 御中',
        style: pw.TextStyle(
          fontSize: 17,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
      pw.SizedBox(height: 10),
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.blueGrey600, width: 0.8),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              '御請求金額',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              _yen(invoice.grandTotalYen),
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 8),
      pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.blueGrey600, width: 0.8),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('振込先', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 3),
            pw.Text('請求書設定で登録した銀行口座を使用します。'),
          ],
        ),
      ),
      pw.SizedBox(height: 12),
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        color: PdfColors.blueGrey100,
        child: pw.Text(
          '件名 / 工期  ${invoice.billingPeriod}',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
      ),
      pw.SizedBox(height: 8),
      pw.TableHelper.fromTextArray(
        headers: const ['整理番号', '内容', '人工', '残業', '金額'],
        data: [
          for (var i = 0; i < rows.length; i++)
            [
              (i + 1).toString(),
              rows[i][0],
              rows[i][1],
              '',
              rows[i][3],
            ],
        ],
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        headerDecoration: const pw.BoxDecoration(
          color: PdfColors.blueGrey100,
        ),
        cellPadding: const pw.EdgeInsets.symmetric(
          horizontal: 6,
          vertical: 5,
        ),
        headerAlignments: const {
          0: pw.Alignment.center,
          2: pw.Alignment.centerRight,
          3: pw.Alignment.centerRight,
          4: pw.Alignment.centerRight,
        },
        cellAlignments: const {
          0: pw.Alignment.center,
          2: pw.Alignment.centerRight,
          3: pw.Alignment.centerRight,
          4: pw.Alignment.centerRight,
        },
        columnWidths: const {
          0: pw.FlexColumnWidth(.8),
          1: pw.FlexColumnWidth(3.6),
          2: pw.FlexColumnWidth(1),
          3: pw.FlexColumnWidth(1),
          4: pw.FlexColumnWidth(1.6),
        },
      ),
      pw.SizedBox(height: 18),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Container(
          width: 230,
          child: pw.Column(
            children: [
              _totalRow('小計', invoice.subtotalYen),
              _totalRow('消費税', invoice.taxYen),
              pw.Divider(thickness: 1.5),
              _totalRow(
                '合計(税込)',
                invoice.grandTotalYen,
                strong: true,
              ),
            ],
          ),
        ),
      ),
    ];
  }

  static pw.Widget _totalRow(
    String label,
    int value, {
    bool strong = false,
  }) {
    final style = pw.TextStyle(
      fontSize: strong ? 14 : 11,
      fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: style),
          pw.Text(_yen(value), style: style),
        ],
      ),
    );
  }

  static String _quantity(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  static String _yen(int value) {
    final negative = value < 0;
    final digits = value.abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return '${negative ? '-' : ''}¥$buffer';
  }
}

class InvoicePdfPreviewPage extends StatelessWidget {
  const InvoicePdfPreviewPage({
    super.key,
    required this.invoices,
    this.title,
  });

  final List<InvoiceCalculationResult> invoices;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title ?? '請求書PDFプレビュー')),
      body: PdfPreview(
        initialPageFormat: PdfPageFormat.a4,
        canChangePageFormat: false,
        canChangeOrientation: false,
        allowPrinting: true,
        allowSharing: true,
        pdfFileName: InvoicePdfService.fileNameFor(
          invoices,
          title: title,
        ),
        build: (format) => InvoicePdfService.buildPdf(
          invoices,
          title: title,
          format: format,
        ),
      ),
    );
  }
}
