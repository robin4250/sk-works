import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../domain/invoice_engine.dart';

class InvoicePdfService {
  const InvoicePdfService._();

  static Future<Uint8List> buildPdf(
    List<InvoiceCalculationResult> invoices, {
    String? title,
  }) {
    if (invoices.isEmpty) {
      throw ArgumentError.value(invoices, 'invoices', 'must not be empty');
    }
    return Printing.convertHtml(
      format: PdfPageFormat.a4,
      html: buildHtml(invoices, title: title),
    );
  }

  static Future<bool> printInvoices(
    List<InvoiceCalculationResult> invoices, {
    String? title,
  }) {
    final name = _fileName(invoices, title: title);
    return Printing.layoutPdf(
      name: name,
      format: PdfPageFormat.a4,
      onLayout: (format) => Printing.convertHtml(
        format: format,
        html: buildHtml(invoices, title: title),
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
      filename: _fileName(invoices, title: title),
      subject: subject,
      body: body,
    );
  }

  static String buildHtml(
    List<InvoiceCalculationResult> invoices, {
    String? title,
  }) {
    final documentTitle = _escape(
      title ??
          (invoices.length == 1
              ? '${invoices.first.billingPeriod} 請求書'
              : '請求書まとめ'),
    );

    final body = invoices
        .map(
          (invoice) => '''
<section class="invoice">
  <header>
    <h1>請求書</h1>
    <div class="period">${_escape(invoice.billingPeriod)}</div>
  </header>

  <div class="recipient">${_escape(invoice.customerId)} 御中</div>

  <table class="details">
    <thead>
      <tr>
        <th>現場 / 明細</th>
        <th class="num">数量</th>
        <th class="num">単価</th>
        <th class="num">金額</th>
      </tr>
    </thead>
    <tbody>
      ${invoice.siteCalculations.map(_siteHtml).join()}
    </tbody>
  </table>

  <table class="totals">
    <tr><th>小計</th><td>${_yen(invoice.subtotalYen)}</td></tr>
    <tr><th>消費税</th><td>${_yen(invoice.taxYen)}</td></tr>
    <tr class="grand"><th>請求合計</th><td>${_yen(invoice.grandTotalYen)}</td></tr>
  </table>
</section>
''',
        )
        .join('<div class="page-break"></div>');

    return '''<!doctype html>
<html lang="ja">
<head>
<meta charset="utf-8">
<title>$documentTitle</title>
<style>
  @page { size: A4; margin: 14mm; }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    color: #111;
    font-family: -apple-system, BlinkMacSystemFont, "Hiragino Sans",
      "Yu Gothic", "Noto Sans JP", sans-serif;
    font-size: 11pt;
  }
  .invoice { width: 100%; }
  header {
    display: flex;
    justify-content: space-between;
    align-items: baseline;
    border-bottom: 2px solid #222;
    margin-bottom: 18px;
  }
  h1 { margin: 0 0 8px; font-size: 26pt; }
  .period { font-size: 12pt; font-weight: 700; }
  .recipient {
    font-size: 16pt;
    font-weight: 700;
    margin: 20px 0 24px;
  }
  table { width: 100%; border-collapse: collapse; }
  .details th, .details td {
    border: 1px solid #bbb;
    padding: 7px 8px;
    vertical-align: top;
  }
  .details thead th { background: #f2f2f2; }
  .site-row td {
    background: #fafafa;
    font-weight: 700;
  }
  .num { text-align: right; white-space: nowrap; }
  .totals {
    width: 52%;
    margin: 18px 0 0 auto;
  }
  .totals th, .totals td {
    border-bottom: 1px solid #bbb;
    padding: 7px 8px;
  }
  .totals th { text-align: left; }
  .totals td { text-align: right; white-space: nowrap; }
  .totals .grand th, .totals .grand td {
    border-top: 2px solid #222;
    border-bottom: 2px solid #222;
    font-size: 14pt;
    font-weight: 700;
  }
  .page-break { page-break-after: always; }
</style>
</head>
<body>
$body
</body>
</html>''';
  }

  static String _siteHtml(SiteInvoiceCalculation site) {
    final rows = <String>[
      '<tr class="site-row"><td colspan="4">${_escape(site.siteName)}</td></tr>',
      ...site.lines.map(
        (line) => '''
<tr>
  <td>${_escape(line.label)}</td>
  <td class="num">${_quantity(line.quantity)}</td>
  <td class="num">${_yen(line.unitPriceYen)}</td>
  <td class="num">${_yen(line.amountYen)}</td>
</tr>''',
      ),
    ];

    if (site.manualAdjustmentYen != 0) {
      rows.add(
        '<tr><td>調整</td><td></td><td></td><td class="num">${_yen(site.manualAdjustmentYen)}</td></tr>',
      );
    }
    if (site.welfareAmountYen != 0) {
      rows.add(
        '<tr><td>法定福利費</td><td></td><td></td><td class="num">${_yen(site.welfareAmountYen)}</td></tr>',
      );
    }

    return rows.join();
  }

  static String _quantity(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
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

  static String _fileName(
    List<InvoiceCalculationResult> invoices, {
    String? title,
  }) {
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

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
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
        pdfFileName: InvoicePdfService._fileName(invoices, title: title),
        build: (format) => Printing.convertHtml(
          format: format,
          html: InvoicePdfService.buildHtml(invoices, title: title),
        ),
      ),
    );
  }
}
