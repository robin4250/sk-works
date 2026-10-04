import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../domain/invoice_engine.dart';
import 'invoice_settings_repository.dart';

class InvoicePdfService {
  const InvoicePdfService._();

  static Future<Uint8List> buildPdf(
    List<InvoiceCalculationResult> invoices, {
    String? title,
    InvoiceSettingsData? settings,
    PdfPageFormat format = PdfPageFormat.a4,
  }) async {
    if (invoices.isEmpty) {
      throw ArgumentError.value(invoices, 'invoices', 'must not be empty');
    }
    final effectiveSettings = settings ?? await _loadSettings();

    final regular = await PdfGoogleFonts.notoSansJPRegular();
    final bold = await PdfGoogleFonts.notoSansJPBold();
    final document = pw.Document(
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );
    for (final invoice in invoices) {
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(
            13 * PdfPageFormat.mm,
            10 * PdfPageFormat.mm,
            13 * PdfPageFormat.mm,
            10 * PdfPageFormat.mm,
          ),
          build: (_) => _sheet(invoice, effectiveSettings),
        ),
      );
    }
    return document.save();
  }

  static Future<bool> printInvoices(
    List<InvoiceCalculationResult> invoices, {
    String? title,
    InvoiceSettingsData? settings,
  }) =>
      Printing.layoutPdf(
        name: fileNameFor(invoices, title: title),
        format: PdfPageFormat.a4,
        onLayout: (_) => buildPdf(
          invoices,
          title: title,
          settings: settings,
        ),
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

  static pw.Widget _sheet(
    InvoiceCalculationResult invoice,
    InvoiceSettingsData? settings,
  ) {
    final blue = PdfColor.fromHex('#8199B5');
    final pale = PdfColor.fromHex('#E7ECF2');
    final rows = <_InvoiceFormRow>[];
    var baseTotal = 0;
    var welfareTotal = 0;
    var adjustmentTotal = 0;

    for (final site in invoice.siteCalculations) {
      for (var index = 0; index < site.lines.length; index++) {
        final line = site.lines[index];
        final isOvertime = line.label.contains('残業');
        rows.add(
          _InvoiceFormRow(
            siteName: index == 0 ? site.siteName : '',
            content: line.label,
            quantity: isOvertime ? '' : _quantity(line.quantity),
            overtime: isOvertime ? _quantity(line.quantity) : '',
            amount: _number(line.amountYen),
          ),
        );
        baseTotal += line.amountYen;
      }
      if (site.welfareAmountYen != 0) {
        rows.add(
          _InvoiceFormRow(
            siteName: '',
            content: '法定福利費',
            quantity: '',
            overtime: '',
            amount: _number(site.welfareAmountYen),
          ),
        );
        welfareTotal += site.welfareAmountYen;
      }
      if (site.manualAdjustmentYen != 0) {
        rows.add(
          _InvoiceFormRow(
            siteName: '',
            content: '値引き・調整',
            quantity: '',
            overtime: '',
            amount: _number(site.manualAdjustmentYen),
          ),
        );
        adjustmentTotal += site.manualAdjustmentYen;
      }
    }
    while (rows.length < 10) {
      rows.add(const _InvoiceFormRow.empty());
    }

    final bank = [
      settings?.bankName ?? '',
      settings?.bankBranch ?? '',
      settings?.bankAccountType ?? '',
      settings?.bankAccountNumber ?? '',
    ].where((value) => value.trim().isNotEmpty).join('　');

    final subject = (settings?.invoiceSubject ?? '').trim();
    final issueDate = invoice.issueDate ?? _monthEnd(invoice);
    final workPeriod = _workPeriod(invoice);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Stack(
          children: [
            pw.Align(
              alignment: pw.Alignment.topCenter,
              child: pw.Text(
                '御　請　求　書',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  color: blue,
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 4,
                ),
              ),
            ),
            pw.Align(
              alignment: pw.Alignment.topRight,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    _dateJa(issueDate),
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                  pw.Text(
                    '請求書番号：${invoice.invoiceNumber}',
                    style: pw.TextStyle(fontSize: 8, color: blue),
                  ),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 18),
        pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 4),
          decoration: pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: blue, width: 1.4),
            ),
          ),
          child: pw.Text(
            '${invoice.customerId}　御中',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: 17,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Text(
                '下記の通り、御請求申し上げますので、お支払約定日までに、\n'
                '下記の口座宛にお振り込み頂きますよう宜しくお願い申し上げます。',
                style: pw.TextStyle(fontSize: 8.5, color: blue),
              ),
            ),
            pw.SizedBox(width: 14),
            pw.SizedBox(
              width: 220,
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          settings?.companyName ?? '',
                          style: pw.TextStyle(
                            fontSize: 13,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        if ((settings?.companyPostalCode ?? '').isNotEmpty)
                          pw.Text(
                            '〒${settings!.companyPostalCode}',
                            style: const pw.TextStyle(fontSize: 7.5),
                          ),
                        if ((settings?.companyAddress ?? '').isNotEmpty)
                          pw.Text(
                            settings!.companyAddress,
                            style: const pw.TextStyle(fontSize: 7.5),
                          ),
                        if ((settings?.companyPhone ?? '').isNotEmpty)
                          pw.Text(
                            'TEL：${settings!.companyPhone}',
                            style: const pw.TextStyle(fontSize: 7.5),
                          ),
                        if ((settings?.companyFax ?? '').isNotEmpty)
                          pw.Text(
                            'FAX：${settings!.companyFax}',
                            style: const pw.TextStyle(fontSize: 7.5),
                          ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 7),
                  _companySeal(settings?.companyName ?? ''),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 11),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: blue, width: 1.1),
                ),
                child: pw.Column(
                  children: [
                    pw.Row(
                      children: [
                        pw.Text(
                          '御請求金額',
                          style: pw.TextStyle(
                            color: blue,
                            fontSize: 13,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(width: 10),
                        pw.Expanded(
                          child: pw.Container(
                            padding: const pw.EdgeInsets.symmetric(vertical: 5),
                            decoration: pw.BoxDecoration(
                              border: pw.Border.all(color: blue, width: 1),
                            ),
                            child: pw.Text(
                              _yen(invoice.grandTotalYen),
                              textAlign: pw.TextAlign.center,
                              style: pw.TextStyle(
                                fontSize: 20,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 6),
                    pw.Text(
                      bank.isEmpty ? '振込先：請求書設定の口座情報' : '振込先：$bank',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                    if ((settings?.bankAccountHolder ?? '').trim().isNotEmpty)
                      pw.Text(
                        '口座名義：${settings!.bankAccountHolder}',
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    pw.Text(
                      '（振込手数料は御社にて御負担願います）',
                      style: pw.TextStyle(fontSize: 7.5, color: blue),
                    ),
                  ],
                ),
              ),
            ),
            pw.SizedBox(width: 18),
            pw.Container(
              width: 170,
              height: 83,
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: blue, width: .8),
              ),
              alignment: pw.Alignment.center,
              child: _confirmationStamp(
                settings?.invoiceContactName ?? '',
                issueDate,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: blue, width: .8),
          ),
          child: pw.Row(
            children: [
              pw.Container(
                color: blue,
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                child: pw.Text(
                  '件名 ／ 工期',
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.Expanded(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 7),
                  child: pw.Row(
                    children: [
                      pw.Expanded(
                        child: pw.Text(
                          subject.isEmpty ? '件名未設定' : subject,
                          style: pw.TextStyle(
                            fontSize: 8.5,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                      pw.Text(
                        workPeriod,
                        textAlign: pw.TextAlign.right,
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 7),
        pw.Table(
          border: pw.TableBorder.all(color: blue, width: .55),
          columnWidths: const {
            0: pw.FlexColumnWidth(.75),
            1: pw.FlexColumnWidth(3.3),
            2: pw.FlexColumnWidth(.85),
            3: pw.FlexColumnWidth(1.05),
            4: pw.FlexColumnWidth(1.35),
          },
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: blue),
              children: [
                _cell('整理番号', bold: true, center: true, color: PdfColors.white),
                _cell('内容', bold: true, center: true, color: PdfColors.white),
                _cell('人工', bold: true, center: true, color: PdfColors.white),
                _cell('残業', bold: true, center: true, color: PdfColors.white),
                _cell('金額', bold: true, center: true, color: PdfColors.white),
              ],
            ),
            for (var i = 0; i < rows.length; i++)
              pw.TableRow(
                decoration: pw.BoxDecoration(
                  color: i.isOdd ? pale : PdfColors.white,
                ),
                children: [
                  _cell(rows[i].content.isEmpty ? '' : '${i + 1}', center: true),
                  _cell(
                    rows[i].siteName.isEmpty
                        ? rows[i].content
                        : '${rows[i].siteName}　${rows[i].content}',
                  ),
                  _cell(rows[i].quantity, right: true),
                  _cell(rows[i].overtime, right: true),
                  _cell(rows[i].amount, right: true),
                ],
              ),
          ],
        ),
        pw.SizedBox(height: 7),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.SizedBox(
            width: 315,
            child: pw.Table(
              border: pw.TableBorder.all(color: blue, width: .55),
              columnWidths: const {
                0: pw.FlexColumnWidth(1.25),
                1: pw.FlexColumnWidth(2.4),
              },
              children: [
                _summaryRow('計', baseTotal + welfareTotal + adjustmentTotal, blue),
                _summaryRow('値引き', adjustmentTotal < 0 ? adjustmentTotal : 0, blue),
                _summaryRow(
                  '消費税(${(invoice.taxRateBps / 100).toStringAsFixed(invoice.taxRateBps % 100 == 0 ? 0 : 2)}%)',
                  invoice.taxYen,
                  blue,
                ),
                _summaryRow('合計(税込)', invoice.grandTotalYen, blue, strong: true),
              ],
            ),
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Container(
          height: 39,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: blue, width: .8),
          ),
          child: pw.Row(
            children: [
              pw.Container(
                width: 130,
                color: blue,
                alignment: pw.Alignment.center,
                child: pw.Text(
                  'お支払約定日',
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.Expanded(
                child: pw.Center(
                  child: pw.Text(
                    (settings?.paymentDueText ?? '').trim().isEmpty
                        ? '未設定'
                        : settings!.paymentDueText,
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ),
              ),
              pw.Container(
                width: 70,
                color: blue,
                alignment: pw.Alignment.center,
                child: pw.Text(
                  '金額',
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(
                width: 120,
                child: pw.Center(
                  child: pw.Text(
                    _yen(invoice.grandTotalYen),
                    style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Container(
          height: 60,
          padding: const pw.EdgeInsets.all(7),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: blue, width: .8),
          ),
          child: pw.Text(
            '備考：${settings?.footerNote ?? ''}',
            style: const pw.TextStyle(fontSize: 8),
          ),
        ),
      ],
    );
  }

  static pw.Widget _confirmationStamp(String name, DateTime date) {
    final red = PdfColor.fromHex('#B83232');
    final label = name.trim().isEmpty ? '担当者' : name.trim();
    return pw.Container(
      width: 58,
      height: 58,
      decoration: pw.BoxDecoration(
        shape: pw.BoxShape.circle,
        border: pw.Border.all(color: red, width: 1.5),
      ),
      alignment: pw.Alignment.center,
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text('確認', style: pw.TextStyle(color: red, fontSize: 7)),
          pw.Text(
            '${date.year}.${date.month}.${date.day}',
            style: pw.TextStyle(color: red, fontSize: 6),
          ),
          pw.Text(
            label,
            style: pw.TextStyle(
              color: red,
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _companySeal(String companyName) {
    final red = PdfColor.fromHex('#B83232');
    final text = companyName.trim().isEmpty ? '会社印' : companyName.trim();
    return pw.Container(
      width: 48,
      height: 48,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: red, width: 1.5),
      ),
      padding: const pw.EdgeInsets.all(3),
      alignment: pw.Alignment.center,
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        maxLines: 4,
        style: pw.TextStyle(
          color: red,
          fontSize: 6.5,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  static DateTime _monthEnd(InvoiceCalculationResult invoice) {
    if (invoice.periodEnd != null) return invoice.periodEnd!;
    final match = RegExp(r'(\\d{4})年(\\d{1,2})月').firstMatch(
      invoice.billingPeriod,
    );
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
      return await repository.load();
    } catch (_) {
      return null;
    }
  }

  static pw.TableRow _summaryRow(
    String label,
    int value,
    PdfColor blue, {
    bool strong = false,
  }) =>
      pw.TableRow(
        children: [
          pw.Container(
            color: blue,
            padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            child: pw.Text(
              label,
              style: pw.TextStyle(
                color: PdfColors.white,
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            child: pw.Text(
              value == 0 && label == '値引き' ? '' : _yen(value),
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(
                fontSize: strong ? 10 : 8.5,
                fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ),
        ],
      );

  static pw.Widget _cell(
    String text, {
    bool bold = false,
    bool right = false,
    bool center = false,
    PdfColor? color,
  }) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3.2),
        child: pw.Text(
          text,
          textAlign: right
              ? pw.TextAlign.right
              : center
                  ? pw.TextAlign.center
                  : pw.TextAlign.left,
          style: pw.TextStyle(
            fontSize: 7.5,
            color: color,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      );

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
    required this.overtime,
    required this.amount,
  });

  const _InvoiceFormRow.empty()
      : siteName = '',
        content = '',
        quantity = '',
        overtime = '',
        amount = '';

  final String siteName;
  final String content;
  final String quantity;
  final String overtime;
  final String amount;
}

class InvoicePdfPreviewPage extends StatefulWidget {
  const InvoicePdfPreviewPage({
    super.key,
    required this.invoices,
    this.title,
  });

  final List<InvoiceCalculationResult> invoices;
  final String? title;

  @override
  State<InvoicePdfPreviewPage> createState() => _InvoicePdfPreviewPageState();
}

class _InvoicePdfPreviewPageState extends State<InvoicePdfPreviewPage> {
  late final Future<InvoiceSettingsData?> _settings = _loadSettings();

  Future<InvoiceSettingsData?> _loadSettings() async {
    final repository = InvoiceSettingsRepository.maybeCreate();
    if (repository == null) return null;
    try {
      return await repository.load();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? '請求書PDFプレビュー')),
      body: FutureBuilder<InvoiceSettingsData?>(
        future: _settings,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return Column(
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  'ピンチ操作で拡大・縮小できます',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Expanded(
                child: PdfPreview(
            initialPageFormat: PdfPageFormat.a4,
            canChangePageFormat: false,
            canChangeOrientation: false,
            allowPrinting: true,
            allowSharing: true,
            pdfFileName: InvoicePdfService.fileNameFor(
              widget.invoices,
              title: widget.title,
            ),
            build: (_) => InvoicePdfService.buildPdf(
              widget.invoices,
              title: widget.title,
              settings: snapshot.data,
            ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
