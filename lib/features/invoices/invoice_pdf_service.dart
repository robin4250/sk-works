import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../domain/invoice_engine.dart';
import '../shared/company_seal_pdf.dart';
import 'invoice_approval_repository.dart';
import 'invoice_settings_repository.dart';

class InvoicePdfService {
  const InvoicePdfService._();

  static Future<Uint8List> buildPdf(
    List<InvoiceCalculationResult> invoices, {
    String? title,
    InvoiceSettingsData? settings,
    PdfPageFormat format = PdfPageFormat.a4,
    pw.Font? regularFont,
    pw.Font? boldFont,
    Map<String, List<InvoiceApprovalRecord>>? approvalsByInvoice,
  }) async {
    if (invoices.isEmpty) {
      throw ArgumentError.value(invoices, 'invoices', 'must not be empty');
    }
    final effectiveSettings = settings ?? await _loadSettings();

    final regular = regularFont ?? await PdfGoogleFonts.notoSansJPRegular();
    final bold = boldFont ?? await PdfGoogleFonts.notoSansJPBold();
    final document = pw.Document(
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );
    final approvalRepository = InvoiceApprovalRepository.maybeCreate();
    for (final invoice in invoices) {
      List<InvoiceApprovalRecord> approvals = const [];
      if (approvalsByInvoice?.containsKey(invoice.invoiceId) == true) {
        approvals = List<InvoiceApprovalRecord>.unmodifiable(
          approvalsByInvoice![invoice.invoiceId]!,
        );
      } else if (approvalRepository != null && invoice.invoiceId.isNotEmpty) {
        try {
          approvals = await approvalRepository.loadForInvoice(
            invoice.invoiceId,
          );
        } catch (_) {
          approvals = const [];
        }
      }
      final detailPageCount = (_detailRows(invoice).length / 35).ceil();
      final pageCount = detailPageCount == 0 ? 1 : detailPageCount;
      for (var pageIndex = 0; pageIndex < pageCount; pageIndex++) {
        document.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: pw.EdgeInsets.zero,
            build: (_) => _sheet(
              invoice,
              effectiveSettings,
              approvals,
              pageIndex: pageIndex,
              pageCount: pageCount,
            ),
          ),
        );
      }
    }
    return document.save();
  }

  static Future<bool> printInvoices(
    List<InvoiceCalculationResult> invoices, {
    String? title,
    InvoiceSettingsData? settings,
  }) => Printing.layoutPdf(
    name: fileNameFor(invoices, title: title),
    format: PdfPageFormat.a4,
    onLayout: (_) => buildPdf(invoices, title: title, settings: settings),
  );

  static Future<bool> shareInvoices(
    List<InvoiceCalculationResult> invoices, {
    String? title,
    String? subject,
    String? body,
    InvoiceSettingsData? settings,
  }) async {
    final bytes = await buildPdf(invoices, title: title, settings: settings);
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
    return '${base.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').replaceAll(RegExp(r'\s+'), '_')}.pdf';
  }

  static String buildTextSnapshot(
    List<InvoiceCalculationResult> invoices, {
    String? title,
  }) {
    final buffer = StringBuffer();
    if (title != null && title.trim().isNotEmpty) buffer.writeln(title.trim());
    for (final invoice in invoices) {
      buffer
        ..writeln('御請求書')
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
        if (site.welfareAmountYen != 0) {
          buffer.writeln('法定福利費 ${_yen(site.welfareAmountYen)}');
        }
        if (site.manualAdjustmentYen != 0) {
          buffer.writeln('値引き・調整 ${_yen(site.manualAdjustmentYen)}');
        }
      }
      buffer
        ..writeln('計 ${_yen(invoice.subtotalYen)}')
        ..writeln('消費税 ${_yen(invoice.taxYen)}')
        ..writeln('合計(税込) ${_yen(invoice.grandTotalYen)}')
        ..writeln('請求合計 ${_yen(invoice.grandTotalYen)}');
    }
    return buffer.toString();
  }

  // Adopted invoice v8 uses absolute A4 coordinates in PDF points.
  static List<_InvoiceFormRow> _detailRows(InvoiceCalculationResult invoice) {
    final rows = <_InvoiceFormRow>[];
    for (final site in invoice.siteCalculations) {
      for (var i = 0; i < site.lines.length; i++) {
        final line = site.lines[i];
        rows.add(
          _InvoiceFormRow(
            siteName: line.siteLabel.trim().isNotEmpty
                ? line.siteLabel
                : (i == 0 ? site.siteName : '〃'),
            content: (line.workContent ?? line.label).trim(),
            quantity: line.quantity == 0 ? '' : _quantity(line.quantity),
            unitPrice: (line.unitPriceText ?? '').trim().isNotEmpty
                ? line.unitPriceText!
                : _number(line.unitPriceYen),
            amount: _number(line.amountYen),
          ),
        );
      }
      if (site.welfareAmountYen != 0) {
        rows.add(
          _InvoiceFormRow(
            siteName: '〃',
            content: '法定福利費',
            quantity: '',
            unitPrice: '',
            amount: _number(site.welfareAmountYen),
          ),
        );
      }
      if (site.manualAdjustmentYen != 0) {
        rows.add(
          _InvoiceFormRow(
            siteName: '〃',
            content: '値引き・調整',
            quantity: '',
            unitPrice: '',
            amount: _number(site.manualAdjustmentYen),
          ),
        );
      }
    }
    return rows;
  }

  static pw.Widget _sheet(
    InvoiceCalculationResult invoice,
    InvoiceSettingsData? settings,
    List<InvoiceApprovalRecord> approvals, {
    int pageIndex = 0,
    int pageCount = 1,
  }) {
    final blue = PdfColor.fromHex('#138BE1');
    final ink = PdfColor.fromHex('#163F76');
    final border = PdfColor.fromHex('#79CAE9');
    final pale = PdfColor.fromHex('#EFF9FD');
    final children = <pw.Widget>[];
    void box(
      double x,
      double y,
      double w,
      double h, {
      PdfColor? fill,
      double radius = 5,
      double line = .42,
    }) {
      children.add(
        pw.Positioned(
          left: x,
          top: y,
          child: pw.Container(
            width: w,
            height: h,
            decoration: pw.BoxDecoration(
              color: fill,
              border: pw.Border.all(color: border, width: line),
              borderRadius: pw.BorderRadius.circular(radius),
            ),
          ),
        ),
      );
    }

    void text(
      String value,
      double x,
      double y,
      double w, {
      double size = 7,
      bool bold = false,
      PdfColor? color,
      pw.TextAlign align = pw.TextAlign.left,
      double h = 18,
      int maxLines = 2,
    }) {
      children.add(
        pw.Positioned(
          left: x,
          top: y,
          child: pw.SizedBox(
            width: w,
            height: h,
            child: pw.Text(
              value,
              textAlign: align,
              maxLines: maxLines,
              style: pw.TextStyle(
                fontSize: size,
                color: color ?? ink,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ),
        ),
      );
    }

    void line(
      double x,
      double y,
      double w,
      double h, {
      PdfColor? color,
      double width = .25,
    }) {
      children.add(
        pw.Positioned(
          left: x,
          top: y,
          child: pw.Container(
            width: w == 0 ? width : w,
            height: h == 0 ? width : h,
            color: color ?? border,
          ),
        ),
      );
    }

    const right = 567.2756;
    box(16, 16, 563.2756, 809.8898, radius: 3, line: .55);
    text(
      '請　求　書',
      222.64,
      28,
      150,
      size: 20,
      bold: true,
      align: pw.TextAlign.center,
      h: 27,
    );
    line(222.64, 55, 150, 0, color: blue, width: .55);
    text(
      'I N V O I C E',
      222.64,
      62,
      150,
      size: 7,
      color: blue,
      align: pw.TextAlign.center,
    );
    text('請求書番号', 450.3, 32, 65);
    text(invoice.invoiceNumber, 515, 32, 52.2756, align: pw.TextAlign.right);
    text('発行日', 450.3, 47, 50);
    text(
      _dateJa(invoice.issueDate ?? _monthEnd(invoice)),
      490,
      47,
      77.2756,
      align: pw.TextAlign.right,
    );
    box(28, 80, 266, 96);
    box(28, 80, 266, 20, fill: pale, radius: 0, line: .3);
    text('御 請 求 先', 38, 86, 246, size: 9, bold: true);
    text('${invoice.customerId} 御中', 38, 111, 246, size: 11, bold: true, h: 23);
    if (invoice.customerPostalCode.trim().isNotEmpty) {
      text('〒${invoice.customerPostalCode}', 38, 133, 246);
    }
    if (invoice.customerAddress.trim().isNotEmpty) {
      text(invoice.customerAddress, 38, 148, 246, h: 27);
    }
    box(316, 80, right - 316, 55);
    box(316, 80, 104, 31, fill: blue, radius: 0, line: .3);
    box(316, 111, 104, 24, fill: pale, radius: 0, line: .3);
    text('ご請求金額（税込）', 332, 92, 86, size: 8, bold: true, color: PdfColors.white);
    text(
      _yen(invoice.grandTotalYen),
      424,
      86,
      131.2756,
      size: 18,
      bold: true,
      align: pw.TextAlign.right,
      h: 25,
    );
    text('約定日', 356, 120, 50, size: 8);
    text(
      settings?.paymentDueText ?? '',
      423,
      120,
      132.2756,
      size: 8,
      align: pw.TextAlign.right,
    );
    box(316, 143, right - 316, 88);
    text('　お振込先', 330, 156, 220, size: 9, bold: true);
    final bankValues = [
      settings?.bankName ?? '',
      settings?.bankBranch ?? '',
      settings?.bankAccountType ?? '',
      settings?.bankAccountNumber ?? '',
      settings?.bankAccountHolder ?? '',
    ];
    const bankLabels = ['銀行名', '支店名', '口座種別', '口座番号', '口座名義'];
    for (var i = 0; i < bankLabels.length; i++) {
      text(bankLabels[i], 364, 174 + i * 11, 50, size: 5.8);
      text(bankValues[i], 418, 174 + i * 11, 137, size: 6.1);
    }
    if (bankValues.every((v) => v.trim().isEmpty)) {
      text('未登録', 418, 174, 137, size: 6.1, color: PdfColors.red);
    }
    box(28, 186, 266, 20);
    text('件名', 40, 194, 45);
    text(settings?.invoiceSubject ?? '', 90, 193, 196, size: 8, bold: true);
    box(28, 214, 266, 20);
    text('工期', 40, 222, 45);
    text(_workPeriod(invoice), 90, 222, 196);
    const gridBottom = 669.8898;
    const rowHeight = (gridBottom - 262) / 35;
    box(28, 244, right - 28, gridBottom - 244, radius: 0, line: .3);
    box(28, 244, right - 28, 18, fill: pale, radius: 0, line: .3);
    const xs = [28.0, 62.0, 178.0, 304.0, 366.0, 408.0, 490.0, right];
    const headings = ['No.', '現場名', '工事内容・摘要', '期間', '人数', '単価（円）', '金額（円）'];
    for (var i = 0; i < headings.length; i++) {
      text(
        headings[i],
        xs[i] + 3,
        250,
        xs[i + 1] - xs[i] - 6,
        size: 6.2,
        align: pw.TextAlign.center,
      );
      if (i > 0) line(xs[i], 244, 0, gridBottom - 244);
    }
    final allRows = _detailRows(invoice);
    final rows = allRows.skip(pageIndex * 35).take(35).toList();
    while (rows.length < 35) {
      rows.add(const _InvoiceFormRow.empty());
    }
    for (var i = 0; i < 35; i++) {
      final row = rows[i];
      final y = 262 + rowHeight * i;
      line(
        28,
        y + rowHeight,
        right - 28,
        0,
        color: PdfColor.fromHex('#B9E5F2'),
        width: .2,
      );
      final values = [
        '${pageIndex * 35 + i + 1}',
        row.siteName,
        row.content,
        '',
        row.quantity,
        row.unitPrice,
        row.amount,
      ];
      for (var col = 0; col < values.length; col++) {
        text(
          values[col],
          xs[col] + 3,
          y + 3,
          xs[col + 1] - xs[col] - 6,
          size: 5.4,
          align: col == 0 || col == 3 || col == 4
              ? pw.TextAlign.center
              : col >= 5
              ? pw.TextAlign.right
              : pw.TextAlign.left,
          h: rowHeight - 3,
        );
      }
    }
    box(28, 674.8898, 306, 63);
    text('備考', 40, 684, 30, size: 8.5, bold: true);
    final note = (settings?.footerNote ?? '').trim();
    if (note.isEmpty) {
      text('・上記の通りご請求申し上げます。', 64, 688, 260, size: 5.5);
      text('・恐れ入りますが、振込手数料は貴社にてご負担くださいますようお願い申し上げます。', 64, 701, 260, size: 5.5);
      text('・ご不明な点がございましたら、担当者までご連絡ください。', 64, 714, 260, size: 5.5);
    } else {
      text(note, 64, 688, 260, size: 5.5, h: 42, maxLines: 5);
    }
    box(344, 674.8898, right - 344, 63);
    final totals = [invoice.subtotalYen, invoice.taxYen, invoice.grandTotalYen];
    final labels = [
      '小計（税抜）',
      '消費税（${_quantity(invoice.taxRateBps / 100)}%）',
      'ご請求金額（税込）',
    ];
    for (var i = 0; i < 3; i++) {
      text(labels[i], 354, 683 + i * 21, 100, size: 6.5);
      text(
        i == 2 ? _yen(totals[i]) : _number(totals[i]),
        453,
        i == 2 ? 720 : 684 + i * 21,
        104.2756,
        size: i == 2 ? 14 : 7.5,
        bold: i == 2,
        align: pw.TextAlign.right,
        h: 21,
      );
    }
    box(28, 744.8898, right - 28, 70);
    line(377.2756, 749.8898, 0, 60);
    text(
      settings?.companyName ?? '',
      50,
      756,
      285,
      size: 11,
      bold: true,
      color: PdfColors.black,
      align: pw.TextAlign.center,
      h: 23,
    );
    text(
      '${(settings?.companyPostalCode ?? '').isEmpty ? '' : '〒${settings!.companyPostalCode} '}${settings?.companyAddress ?? ''}',
      50,
      784,
      285,
      size: 6,
      align: pw.TextAlign.center,
    );
    text(
      [
        if ((settings?.companyPhone ?? '').isNotEmpty)
          'TEL ${settings!.companyPhone}',
        if ((settings?.companyFax ?? '').isNotEmpty)
          'FAX ${settings!.companyFax}',
      ].join('　'),
      50,
      797,
      285,
      size: 6,
      align: pw.TextAlign.center,
    );
    children.add(
      pw.Positioned(
        left: 230.1378,
        top: 750.6701,
        child: pw.SizedBox(
          width: 42,
          height: 40.4394,
          child: pw.FittedBox(
            fit: pw.BoxFit.fill,
            child: CompanySealPdf.build(settings?.companyName ?? ''),
          ),
        ),
      ),
    );
    box(384.2756, 749.8898, 176, 60, line: .3);
    box(384.2756, 752.8898, 176, 15, fill: pale, radius: 0, line: .3);
    text('確 認 印', 384.2756, 756, 176, size: 7, align: pw.TextAlign.center);
    for (var i = 0; i < 3; i++) {
      final x = 384.2756 + i * 176 / 3;
      if (i > 0) line(x, 767.8898, 0, 42, width: .3);
      if (i < approvals.length && approvals[i].approved) {
        children.add(
          pw.Positioned(
            left: x + 15.3333,
            top: 775.8898,
            child: pw.SizedBox(
              width: 28,
              height: 28,
              child: pw.FittedBox(child: _datedApprovalStamp(approvals[i])),
            ),
          ),
        );
      } else {
        // A neutral empty guide is not an approval stamp.
        children.add(
          pw.Positioned(
            left: x + 15.3333,
            top: 775.8898,
            child: pw.Container(
              width: 28,
              height: 28,
              decoration: pw.BoxDecoration(
                shape: pw.BoxShape.circle,
                border: pw.Border.all(
                  color: PdfColor.fromHex('#B7BEC6'),
                  width: .55,
                ),
              ),
            ),
          ),
        );
      }
    }
    if (pageCount > 1) {
      text(
        '${pageIndex + 1} / $pageCount',
        510,
        817,
        57,
        size: 5,
        align: pw.TextAlign.right,
      );
    }
    return pw.Stack(children: children);
  }

  static pw.Widget _datedApprovalStamp(InvoiceApprovalRecord record) {
    final red = PdfColor.fromHex('#D9272E');
    final date = record.stampDisplayDate;
    final surname = _surname(record.name);
    return pw.Container(
      width: 36,
      height: 36,
      decoration: pw.BoxDecoration(
        shape: pw.BoxShape.circle,
        border: pw.Border.all(color: red, width: 1.5),
      ),
      child: pw.Column(
        children: [
          pw.Expanded(
            child: pw.Center(
              child: pw.Text(
                record.stampRole == 'approval' ? '承認' : '確認',
                style: pw.TextStyle(
                  color: red,
                  fontSize: 5.6,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ),
          pw.Container(height: .55, color: red),
          pw.Expanded(
            child: pw.Center(
              child: pw.Text(
                date == null
                    ? ''
                    : '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}',
                style: pw.TextStyle(color: red, fontSize: 4.1),
              ),
            ),
          ),
          pw.Container(height: .55, color: red),
          pw.Expanded(
            child: pw.Center(
              child: pw.Text(
                surname,
                style: pw.TextStyle(
                  color: red,
                  fontSize: 6.1,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _surname(String name) {
    final value = name.trim();
    if (value.isEmpty) return '';
    return value.split(RegExp(r'[\s　]+')).first;
  }

  static DateTime _monthEnd(InvoiceCalculationResult invoice) {
    if (invoice.periodEnd != null) return invoice.periodEnd!;
    final match = RegExp(r'(\d{4})年(\d{1,2})月')
        .firstMatch(invoice.billingPeriod);
    if (match == null) return DateTime.now();
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    return DateTime(year, month + 1, 0);
  }

  static String _workPeriod(InvoiceCalculationResult invoice) {
    final end = _monthEnd(invoice);
    final start = invoice.periodStart ?? DateTime(end.year, end.month, 1);
    return '${start.year}年${start.month}月${start.day}日'
        '～${end.year}年${end.month}月${end.day}日';
  }

  static String _dateJa(DateTime value) =>
      '${value.year}年${value.month}月${value.day}日';

  static Future<InvoiceSettingsData?> _loadSettings() async {
    final repository = InvoiceSettingsRepository.maybeCreate();
    if (repository == null) return null;
    try {
      return await repository.loadForDocument();
    } catch (_) {
      return null;
    }
  }

  static String _quantity(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  static String _yen(int value) => '¥${_number(value)}';

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
}

class _InvoiceFormRow {
  const _InvoiceFormRow({
    required this.siteName,
    required this.content,
    required this.quantity,
    required this.unitPrice,
    required this.amount,
  });

  const _InvoiceFormRow.empty()
    : siteName = '',
      content = '',
      quantity = '',
      unitPrice = '',
      amount = '';

  final String siteName;
  final String content;
  final String quantity;
  final String unitPrice;
  final String amount;
}

class InvoicePdfPreviewPage extends StatefulWidget {
  const InvoicePdfPreviewPage({super.key, required this.invoices, this.title});

  final List<InvoiceCalculationResult> invoices;
  final String? title;

  @override
  State<InvoicePdfPreviewPage> createState() => _InvoicePdfPreviewPageState();
}

class _InvoicePdfPreviewPageState extends State<InvoicePdfPreviewPage> {
  final _approvalRepository = InvoiceApprovalRepository.maybeCreate();
  late Future<_InvoicePreviewData> _previewData;
  int _previewRevision = 0;

  @override
  void initState() {
    super.initState();
    _previewData = _buildPreviewData();
  }

  InvoiceCalculationResult? get _singleInvoice =>
      widget.invoices.length == 1 ? widget.invoices.first : null;

  Future<InvoiceSettingsData?> _loadSettings() async {
    final repository = InvoiceSettingsRepository.maybeCreate();
    if (repository == null) return null;
    try {
      return await repository.loadForDocument();
    } catch (_) {
      return null;
    }
  }

  Future<_InvoicePreviewData> _buildPreviewData() async {
    if (widget.invoices.isEmpty) {
      throw StateError('表示する請求書がありません。');
    }
    final settings = await _loadSettings();
    final pdfBytes = await InvoicePdfService.buildPdf(
      widget.invoices,
      title: widget.title,
      settings: settings,
    );
    if (pdfBytes.isEmpty) {
      throw StateError('PDFデータが空です。');
    }
    final approvals = await _loadApprovals();
    return _InvoicePreviewData(
      pdfBytes: pdfBytes,
      settings: settings,
      approvals: approvals,
    );
  }

  Future<List<InvoiceApprovalRecord>> _loadApprovals() async {
    final invoice = _singleInvoice;
    final repository = _approvalRepository;
    if (invoice == null || repository == null || invoice.invoiceId.isEmpty) {
      return const [];
    }
    try {
      return await repository.loadForInvoice(invoice.invoiceId);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _approve() async {
    final invoice = _singleInvoice;
    final repository = _approvalRepository;
    if (invoice == null || repository == null || invoice.invoiceId.isEmpty) {
      return;
    }
    await repository.approve(invoice.invoiceId);
    if (!mounted) return;
    setState(() {
      _previewRevision++;
      _previewData = _buildPreviewData();
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('請求書を承認しました')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? '請求書PDFプレビュー')),
      body: FutureBuilder<_InvoicePreviewData>(
        future: _previewData,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.picture_as_pdf_outlined, size: 44),
                    const SizedBox(height: 12),
                    const Text(
                      '請求書プレビューを生成できませんでした',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      snapshot.error?.toString() ?? 'PDFデータが空です。',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => setState(() {
                        _previewRevision++;
                        _previewData = _buildPreviewData();
                      }),
                      icon: const Icon(Icons.refresh),
                      label: const Text('再試行'),
                    ),
                  ],
                ),
              ),
            );
          }
          final previewData = snapshot.data!;
          final pdfBytes = previewData.pdfBytes;
          return FutureBuilder<List<InvoiceApprovalRecord>>(
            future: _loadApprovals(),
            builder: (context, approvalSnapshot) {
              final approvals = approvalSnapshot.data ?? const [];
              final canApprove = approvals.any(
                (item) => item.canCurrentUserApprove,
              );
              return Column(
                children: [
                  if (approvals.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              approvals
                                  .map(
                                    (item) =>
                                        '${item.name}：${item.approved ? '承認済み' : '承認待ち'}',
                                  )
                                  .join('　'),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (canApprove)
                            FilledButton.icon(
                              onPressed: _approve,
                              icon: const Icon(Icons.approval_outlined),
                              label: const Text('承認'),
                            ),
                        ],
                      ),
                    ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      'A4を画面幅に合わせて表示します。プレビュー上で拡大・縮小できます。',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      key: ValueKey(_previewRevision),
                      color: Colors.grey.shade200,
                      alignment: Alignment.topCenter,
                      child: PdfPreview(
                        key: ValueKey('invoice_pdf_preview_$_previewRevision'),
                        build: (_) async => pdfBytes,
                        initialPageFormat: PdfPageFormat.a4,
                        canChangePageFormat: false,
                        canChangeOrientation: false,
                        allowPrinting: false,
                        allowSharing: false,
                        maxPageWidth: 595,
                        pdfPreviewPageDecoration: const BoxDecoration(
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x22000000),
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => Printing.layoutPdf(
                                name: InvoicePdfService.fileNameFor(
                                  widget.invoices,
                                  title: widget.title,
                                ),
                                format: PdfPageFormat.a4,
                                onLayout: (_) async => pdfBytes,
                              ),
                              icon: const Icon(Icons.print_outlined),
                              label: const Text('印刷'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => Printing.sharePdf(
                                bytes: pdfBytes,
                                filename: InvoicePdfService.fileNameFor(
                                  widget.invoices,
                                  title: widget.title,
                                ),
                              ),
                              icon: const Icon(Icons.ios_share_outlined),
                              label: const Text('共有'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _InvoicePreviewData {
  const _InvoicePreviewData({
    required this.pdfBytes,
    required this.settings,
    required this.approvals,
  });
  final Uint8List pdfBytes;
  final InvoiceSettingsData? settings;
  final List<InvoiceApprovalRecord> approvals;
}

class _ExactInvoiceScreen extends StatelessWidget {
  const _ExactInvoiceScreen({
    required this.invoice,
    required this.settings,
    required this.approvals,
  });
  final InvoiceCalculationResult invoice;
  final InvoiceSettingsData? settings;
  final List<InvoiceApprovalRecord> approvals;
  static const blue = Color(0xff8199b5);
  static const pale = Color(0xffe7ecf2);

  @override
  Widget build(BuildContext context) {
    final rows = <_InvoiceFormRow>[];
    for (final site in invoice.siteCalculations) {
      for (var index = 0; index < site.lines.length; index++) {
        final line = site.lines[index];
        final siteLabel = line.siteLabel.trim().isNotEmpty
            ? line.siteLabel
            : index == 0
            ? site.siteName
            : '〃';
        final work = (line.workContent ?? line.label).trim();
        final sub = siteLabel == '〃' && work.isNotEmpty;
        rows.add(
          _InvoiceFormRow(
            siteName: sub ? '〃　$work' : siteLabel,
            content: sub ? '' : (work.isEmpty ? '通常作業' : work),
            quantity: line.quantity == 0
                ? ''
                : InvoicePdfService._quantity(line.quantity),
            unitPrice: (line.unitPriceText ?? '').trim().isNotEmpty
                ? line.unitPriceText!.trim()
                : line.unitPriceYen == 0
                ? ''
                : InvoicePdfService._number(line.unitPriceYen),
            amount: InvoicePdfService._number(line.amountYen),
          ),
        );
      }
      if (site.manualAdjustmentYen != 0) {
        rows.add(
          _InvoiceFormRow(
            siteName: '〃　（値引き・調整）',
            content: '',
            quantity: '',
            unitPrice: '',
            amount: InvoicePdfService._number(site.manualAdjustmentYen),
          ),
        );
      }
    }
    while (rows.length < 35) {
      rows.add(const _InvoiceFormRow.empty());
    }
    final bank = [
      settings?.bankName ?? '',
      settings?.bankBranch ?? '',
      settings?.bankAccountType ?? '',
      settings?.bankAccountNumber ?? '',
    ].where((e) => e.trim().isNotEmpty).join('　');
    final issueDate = invoice.issueDate ?? InvoicePdfService._monthEnd(invoice);
    final subject = (settings?.invoiceSubject ?? '').trim();
    final workPeriod = InvoicePdfService._workPeriod(invoice);
    return Material(
      color: Colors.white,
      elevation: 2,
      child: SizedBox(
        width: 595,
        height: 842,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(37, 28, 37, 28),
          child: DefaultTextStyle(
            style: const TextStyle(color: Colors.black87, fontSize: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 40,
                  child: Stack(
                    children: [
                      const Align(
                        alignment: Alignment.topCenter,
                        child: Text(
                          '御　請　求　書',
                          style: TextStyle(
                            color: blue,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 4,
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.topRight,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              InvoicePdfService._dateJa(issueDate),
                              style: const TextStyle(fontSize: 10),
                            ),
                            Text(
                              '請求書番号：${invoice.invoiceNumber}',
                              style: const TextStyle(fontSize: 8, color: blue),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Container(
                        height: 40,
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: blue, width: 1.4),
                          ),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Text(
                              invoice.customerId,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                '御中',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: blue,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    SizedBox(
                      width: 245,
                      child: Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 28),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  settings?.companyName ?? '',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                if ((settings?.companyPostalCode ?? '')
                                    .isNotEmpty)
                                  Text(
                                    '〒${settings!.companyPostalCode}',
                                    style: const TextStyle(fontSize: 7.5),
                                  ),
                                if ((settings?.companyAddress ?? '').isNotEmpty)
                                  Text(
                                    settings!.companyAddress,
                                    style: const TextStyle(fontSize: 7.5),
                                  ),
                                if ((settings?.companyPhone ?? '').isNotEmpty)
                                  Text(
                                    'TEL：${settings!.companyPhone}',
                                    style: const TextStyle(fontSize: 7.5),
                                  ),
                              ],
                            ),
                          ),
                          Positioned(
                            right: 0,
                            top: 0,
                            child: _ScreenSeal(
                              companyName: settings?.companyName ?? '',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          border: Border.all(color: blue, width: 1.1),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const Text(
                                  '御請求金額',
                                  style: TextStyle(
                                    color: blue,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Container(
                                    height: 34,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      border: Border.all(color: blue),
                                    ),
                                    child: Text(
                                      InvoicePdfService._yen(
                                        invoice.grandTotalYen,
                                      ),
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(
                              bank.isEmpty ? '振込先：請求書設定の口座情報' : '振込先：$bank',
                              style: const TextStyle(fontSize: 9),
                            ),
                            if ((settings?.bankAccountHolder ?? '')
                                .trim()
                                .isNotEmpty)
                              Text(
                                '口座名義：${settings!.bankAccountHolder}',
                                style: const TextStyle(fontSize: 8),
                              ),
                            const Text(
                              '（振込手数料は御社にて御負担願います）',
                              style: TextStyle(fontSize: 7.5, color: blue),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 142,
                      height: 66,
                      child: _ScreenApprovals(approvals: approvals),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                const Text(
                  '下記の通り、御請求申し上げますので、お支払約定日までに、\n下記の口座宛にお振り込み頂きますよう宜しくお願い申し上げます。',
                  style: TextStyle(fontSize: 8.5, color: blue),
                ),
                const SizedBox(height: 10),
                Container(
                  height: 30,
                  decoration: BoxDecoration(
                    border: Border.all(color: blue, width: .8),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 92,
                        alignment: Alignment.center,
                        color: blue,
                        child: const Text(
                          '件名 ／ 工期',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 7),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  subject.isEmpty ? '件名未設定' : subject,
                                  style: const TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              Text(
                                workPeriod,
                                style: const TextStyle(fontSize: 8),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 7),
                _ScreenDetailTable(rows: rows),
                const SizedBox(height: 7),
                Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: 315,
                    child: Column(
                      children: [
                        _summary('計', invoice.subtotalYen),
                        _summary('消費税', invoice.taxYen),
                        _summary('合計(税込)', invoice.grandTotalYen, strong: true),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 39,
                  decoration: BoxDecoration(
                    border: Border.all(color: blue, width: .8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _contract(
                          'お支払約定日',
                          (settings?.paymentDueText ?? '').trim().isEmpty
                              ? '未設定'
                              : settings!.paymentDueText,
                        ),
                      ),
                      Container(width: .8, color: blue),
                      Expanded(
                        child: _contract(
                          '金額',
                          InvoicePdfService._yen(invoice.grandTotalYen),
                          strong: true,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 60,
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    border: Border.all(color: blue, width: .8),
                  ),
                  child: Text(
                    '備考：${settings?.footerNote ?? ''}',
                    style: const TextStyle(fontSize: 8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _summary(String label, int value, {bool strong = false}) =>
      Container(
        height: 25,
        decoration: BoxDecoration(border: Border.all(color: blue, width: .55)),
        child: Row(
          children: [
            Container(
              width: 90,
              alignment: Alignment.center,
              color: blue,
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  InvoicePdfService._yen(value),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: strong ? 11 : 9,
                    fontWeight: strong ? FontWeight.w900 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
  static Widget _contract(String label, String value, {bool strong = false}) =>
      Row(
        children: [
          Container(
            width: 92,
            alignment: Alignment.center,
            color: blue,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: strong ? 12 : 9,
                  fontWeight: strong ? FontWeight.w900 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      );
}

class _ScreenDetailTable extends StatelessWidget {
  const _ScreenDetailTable({required this.rows});
  final List<_InvoiceFormRow> rows;
  @override
  Widget build(BuildContext context) => Table(
    border: TableBorder.all(color: _ExactInvoiceScreen.blue, width: .55),
    columnWidths: const {
      0: FlexColumnWidth(2.15),
      1: FlexColumnWidth(2.05),
      2: FlexColumnWidth(.8),
      3: FlexColumnWidth(1.25),
      4: FlexColumnWidth(1.45),
    },
    children: [
      TableRow(
        decoration: const BoxDecoration(color: _ExactInvoiceScreen.blue),
        children: [
          '作業所名',
          '工事内容',
          '数量',
          '単価',
          '請求金額',
        ].map((e) => _cell(e, white: true, center: true)).toList(),
      ),
      for (var i = 0; i < rows.length; i++)
        TableRow(
          decoration: BoxDecoration(
            color: i.isOdd ? _ExactInvoiceScreen.pale : Colors.white,
          ),
          children: [
            _cell(rows[i].siteName),
            _cell(rows[i].content),
            _cell(rows[i].quantity, right: true),
            _cell(rows[i].unitPrice, right: true),
            _cell(rows[i].amount, right: true),
          ],
        ),
    ],
  );
  Widget _cell(
    String s, {
    bool right = false,
    bool center = false,
    bool white = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2.5),
    child: Text(
      s,
      textAlign: center
          ? TextAlign.center
          : right
          ? TextAlign.right
          : TextAlign.left,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 7,
        color: white ? Colors.white : Colors.black87,
        fontWeight: white ? FontWeight.w900 : FontWeight.w500,
      ),
    ),
  );
}

class _ScreenSeal extends StatelessWidget {
  const _ScreenSeal({required this.companyName});
  final String companyName;
  @override
  Widget build(BuildContext context) => Container(
    width: 34,
    height: 34,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xffb33b32), width: 1.4),
    ),
    child: Text(
      companyName.length > 4 ? companyName.substring(0, 4) : companyName,
      textAlign: TextAlign.center,
      maxLines: 2,
      style: const TextStyle(
        fontSize: 7,
        color: Color(0xffb33b32),
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

class _ScreenApprovals extends StatelessWidget {
  const _ScreenApprovals({required this.approvals});
  final List<InvoiceApprovalRecord> approvals;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < 2; i++)
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: _ExactInvoiceScreen.blue, width: .72),
            ),
            child: Column(
              children: [
                Container(
                  height: 17,
                  alignment: Alignment.center,
                  color: _ExactInvoiceScreen.blue,
                  child: Text(
                    i < approvals.length ? approvals[i].name : '確認',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 7,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      i < approvals.length && approvals[i].approved
                          ? '承認済'
                          : '',
                      style: const TextStyle(
                        fontSize: 7,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}
