import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../domain/invoice_engine.dart';
import 'invoice_approval_repository.dart';
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
    final approvalRepository = InvoiceApprovalRepository.maybeCreate();
    for (final invoice in invoices) {
      List<InvoiceApprovalRecord> approvals = const [];
      if (approvalRepository != null && invoice.invoiceId.isNotEmpty) {
        try {
          approvals = await approvalRepository.loadForInvoice(invoice.invoiceId);
        } catch (_) {
          approvals = const [];
        }
      }
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(
            15 * PdfPageFormat.mm,
            14 * PdfPageFormat.mm,
            15 * PdfPageFormat.mm,
            14 * PdfPageFormat.mm,
          ),
          build: (_) => _sheet(
            invoice,
            effectiveSettings,
            approvals,
          ),
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
    List<InvoiceApprovalRecord> approvals,
  ) {
    final blue = PdfColor.fromHex('#8199B5');
    final pale = PdfColor.fromHex('#E7ECF2');
    final rows = <_InvoiceFormRow>[];
    for (final site in invoice.siteCalculations) {
      for (var index = 0; index < site.lines.length; index++) {
        final line = site.lines[index];
        final siteLabel = line.siteLabel.trim().isNotEmpty
            ? line.siteLabel
            : index == 0
                ? site.siteName
                : '〃';
        final rawWorkContent = (line.workContent ?? line.label).trim();
        final workContent = rawWorkContent.isEmpty ? '通常作業' : rawWorkContent;
        final subRowInSiteColumn =
            siteLabel == '〃' && workContent.isNotEmpty;
        rows.add(
          _InvoiceFormRow(
            siteName: subRowInSiteColumn
                ? '〃　$workContent'
                : siteLabel,
            content: subRowInSiteColumn ? '' : workContent,
            quantity: line.quantity == 0 ? '' : _quantity(line.quantity),
            unitPrice: (line.unitPriceText ?? '').trim().isNotEmpty
                ? line.unitPriceText!.trim()
                : line.unitPriceYen == 0
                    ? ''
                    : _number(line.unitPriceYen),
            amount: _number(line.amountYen),
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
            amount: _number(site.manualAdjustmentYen),
          ),
        );
      }
    }
    while (rows.length < 35) {
      rows.add(const _InvoiceFormRow.empty());
    }
    // The reference invoice is a single A4 sheet. Real invoices can exceed
    // the original 10-row sample (the current production invoice has 13
    // detail rows), so compact the detail grid before it can overflow the
    // fixed page and make PdfPreview fail to render.
    final detailRowCount = rows.length;
    final detailFontSize = detailRowCount > 12
        ? 6.1
        : detailRowCount > 10
            ? 6.7
            : 7.5;
    final detailVerticalPadding = detailRowCount > 12
        ? 1.0
        : detailRowCount > 10
            ? 1.8
            : 3.2;

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
                  fontSize: 17,
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
        pw.SizedBox(height: 2),
        // Keep the invoice top compact: customer and issuer share the top row.
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.only(bottom: 4),
                decoration: pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: blue, width: 1.4),
                  ),
                ),
                child: pw.Stack(
                  children: [
                    pw.Align(
                      alignment: pw.Alignment.center,
                      child: pw.Text(
                        invoice.customerId,
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                          fontSize: 17,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                    pw.Align(
                      alignment: pw.Alignment.centerRight,
                      child: pw.Text(
                        '御中',
                        style: pw.TextStyle(
                          fontSize: 10,
                          color: blue,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            pw.SizedBox(width: 14),
            pw.SizedBox(width: 70),
          ],
        ),
        pw.SizedBox(height: 1),
        // Amount and confirmer areas are independent adjacent frames.
        // Keep the amount frame directly below the recipient name row.
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
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
                    pw.SizedBox(height: 5),
                    pw.Text(
                      bank.isEmpty
                          ? '振込先：請求書設定の口座情報'
                          : '振込先：$bank',
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
            pw.SizedBox(width: 4),
            pw.SizedBox(
              width: 142,
              height: 66,
              child: _approvalBoxes(approvals, blue),
            ),
          ],
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          '下記の通り、御請求申し上げますので、お支払約定日までに、\\n'
          '下記の口座宛にお振り込み頂きますよう宜しくお願い申し上げます。',
          style: pw.TextStyle(fontSize: 8.5, color: blue),
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
            0: pw.FlexColumnWidth(2.15),
            1: pw.FlexColumnWidth(2.05),
            2: pw.FlexColumnWidth(.8),
            3: pw.FlexColumnWidth(1.25),
            4: pw.FlexColumnWidth(1.45),
          },
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: blue),
              children: [
                _cell('作業所名', bold: true, center: true, color: PdfColors.white, fontSize: detailFontSize, verticalPadding: detailVerticalPadding),
                _cell('工事内容', bold: true, center: true, color: PdfColors.white, fontSize: detailFontSize, verticalPadding: detailVerticalPadding),
                _cell('数量', bold: true, center: true, color: PdfColors.white, fontSize: detailFontSize, verticalPadding: detailVerticalPadding),
                _cell('単価', bold: true, center: true, color: PdfColors.white, fontSize: detailFontSize, verticalPadding: detailVerticalPadding),
                _cell('請求金額', bold: true, center: true, color: PdfColors.white, fontSize: detailFontSize, verticalPadding: detailVerticalPadding),
              ],
            ),
            for (var i = 0; i < rows.length; i++)
              pw.TableRow(
                decoration: pw.BoxDecoration(
                  color: i.isOdd ? pale : PdfColors.white,
                ),
                children: [
                  _cell(rows[i].siteName, fontSize: detailFontSize, verticalPadding: detailVerticalPadding),
                  _cell(rows[i].content, fontSize: detailFontSize, verticalPadding: detailVerticalPadding),
                  _cell(rows[i].quantity, right: true, fontSize: detailFontSize, verticalPadding: detailVerticalPadding),
                  _cell(rows[i].unitPrice, right: true, fontSize: detailFontSize, verticalPadding: detailVerticalPadding),
                  _cell(rows[i].amount, right: true, fontSize: detailFontSize, verticalPadding: detailVerticalPadding),
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
                _summaryRow('計', invoice.subtotalYen, blue),
                _summaryRow('消費税', invoice.taxYen, blue),
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
              pw.Expanded(
                child: pw.Row(
                  children: [
                    pw.Container(
                      width: 92,
                      color: blue,
                      alignment: pw.Alignment.center,
                      child: pw.Text(
                        'お支払約定日',
                        style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 10,
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
                  ],
                ),
              ),
              pw.Container(width: .8, color: blue),
              pw.Expanded(
                child: pw.Row(
                  children: [
                    pw.Container(
                      width: 92,
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
                    pw.Expanded(
                      child: pw.Center(
                        child: pw.Text(
                          _yen(invoice.grandTotalYen),
                          style: pw.TextStyle(
                            fontSize: 13,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 8),
        pw.SizedBox(height: 7),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(
              child: pw.Container(
                height: 44,
                padding: const pw.EdgeInsets.all(7),
                decoration: pw.BoxDecoration(border: pw.Border.all(color: blue, width: .8)),
                child: pw.Text('備考：${settings?.footerNote ?? ''}', style: const pw.TextStyle(fontSize: 7)),
              ),
            ),
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: pw.Stack(
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text(settings?.companyName ?? '', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: blue)),
                      if ((settings?.companyPostalCode ?? '').isNotEmpty) pw.Text('〒${settings!.companyPostalCode}', style: const pw.TextStyle(fontSize: 6)),
                      if ((settings?.companyAddress ?? '').isNotEmpty) pw.Text(settings!.companyAddress, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 6)),
                      pw.Text([
                        if ((settings?.companyPhone ?? '').isNotEmpty) 'TEL：${settings!.companyPhone}',
                        if ((settings?.companyFax ?? '').isNotEmpty) 'FAX：${settings!.companyFax}',
                      ].join('　'), style: const pw.TextStyle(fontSize: 6)),
                    ],
                  ),
                  pw.Positioned(right: 5, top: -3, child: _companySeal(settings?.companyName ?? '')),
                ],
              ),
            ),
            pw.SizedBox(width: 10),
            pw.SizedBox(width: 142, height: 44, child: _approvalBoxes(approvals, blue)),
          ],
        ),
      ],
    );
  }

  static pw.Widget _approvalBoxes(
    List<InvoiceApprovalRecord> approvals,
    PdfColor blue,
  ) {
    final visible = approvals.take(3).toList();
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) pw.SizedBox(width: 2),
          pw.Expanded(
            child: pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: blue, width: .72),
              ),
              child: pw.Column(
                children: [
                  pw.Container(
                    height: 17,
                    alignment: pw.Alignment.center,
                    decoration: pw.BoxDecoration(
                      border: pw.Border(
                        bottom: pw.BorderSide(color: blue, width: .55),
                      ),
                    ),
                    child: pw.Text(
                      '確認者',
                      style: pw.TextStyle(
                        color: blue,
                        fontSize: 6.5,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.SizedBox(
                    height: 47,
                    child: pw.Center(
                      child: i >= visible.length
                          ? pw.SizedBox()
                          : visible[i].approved
                              ? _confirmationStamp(
                                  visible[i].approvedAt ?? DateTime.now(),
                                  designB: visible[i].position.isEven,
                                )
                              : pw.SizedBox(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  static pw.Widget _confirmationStamp(
    DateTime date, {
    required bool designB,
  }) {
    final red = PdfColor.fromHex('#B83232');
    
    return pw.Container(
      width: 34,
      height: 34,
      decoration: pw.BoxDecoration(
        shape: pw.BoxShape.circle,
        border: pw.Border.all(
          color: red,
          width: designB ? 1.8 : 1.35,
        ),
      ),
      padding: const pw.EdgeInsets.all(2),
      child: pw.Container(
        decoration: designB
            ? pw.BoxDecoration(
                shape: pw.BoxShape.circle,
                border: pw.Border.all(color: red, width: .55),
              )
            : null,
        alignment: pw.Alignment.center,
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            pw.Text(
              designB ? '確認印' : '確認',
              style: pw.TextStyle(
                color: red,
                fontSize: designB ? 5.6 : 5.8,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Container(
              margin: const pw.EdgeInsets.symmetric(vertical: 1.5),
              height: .55,
              color: red,
            ),
            pw.Text(
              '${date.year}.${date.month}.${date.day}',
              style: pw.TextStyle(color: red, fontSize: 4.4),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _companySeal(String companyName) {
    final red = PdfColor.fromHex('#B83232');
    final text = companyName.trim().isEmpty ? '会社印' : companyName.trim();
    // 角印案B: 太い外角枠＋細い内角枠で、角印らしい印影にする。
    return pw.Container(
      width: 48,
      height: 48,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: red, width: 2.1),
      ),
      padding: const pw.EdgeInsets.all(2.2),
      child: pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: red, width: .75),
        ),
        padding: const pw.EdgeInsets.all(2),
        alignment: pw.Alignment.center,
        child: pw.Text(
          text,
          textAlign: pw.TextAlign.center,
          maxLines: 5,
          style: pw.TextStyle(
            color: red,
            fontSize: 6.8,
            fontWeight: pw.FontWeight.bold,
          ),
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
      return await repository.loadForDocument();
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
    double fontSize = 7.5,
    double verticalPadding = 3.2,
  }) =>
      pw.Padding(
        padding: pw.EdgeInsets.symmetric(horizontal: 4, vertical: verticalPadding),
        child: pw.Text(
          text,
          textAlign: right
              ? pw.TextAlign.right
              : center
                  ? pw.TextAlign.center
                  : pw.TextAlign.left,
          style: pw.TextStyle(
            fontSize: fontSize,
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('請求書を承認しました')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? '請求書PDFプレビュー'),
      ),
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
              final canApprove =
                  approvals.any((item) => item.canCurrentUserApprove);
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
                      child: InteractiveViewer(
                        minScale: 0.5,
                        maxScale: 5,
                        boundaryMargin: const EdgeInsets.all(48),
                        child: _ExactInvoiceScreen(
                          invoice: widget.invoices.first,
                          settings: previewData.settings,
                          approvals: previewData.approvals,
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
            : index == 0 ? site.siteName : '〃';
        final work = (line.workContent ?? line.label).trim();
        final sub = siteLabel == '〃' && work.isNotEmpty;
        rows.add(_InvoiceFormRow(
          siteName: sub ? '〃　$work' : siteLabel,
          content: sub ? '' : (work.isEmpty ? '通常作業' : work),
          quantity: line.quantity == 0 ? '' : InvoicePdfService._quantity(line.quantity),
          unitPrice: (line.unitPriceText ?? '').trim().isNotEmpty
              ? line.unitPriceText!.trim()
              : line.unitPriceYen == 0 ? '' : InvoicePdfService._number(line.unitPriceYen),
          amount: InvoicePdfService._number(line.amountYen),
        ));
      }
      if (site.manualAdjustmentYen != 0) {
        rows.add(_InvoiceFormRow(
          siteName: '〃　（値引き・調整）',
          content: '',
          quantity: '',
          unitPrice: '',
          amount: InvoicePdfService._number(site.manualAdjustmentYen),
        ));
      }
    }
    while (rows.length < 35) {
      rows.add(const _InvoiceFormRow.empty());
    }
    final bank = [settings?.bankName ?? '', settings?.bankBranch ?? '',
      settings?.bankAccountType ?? '', settings?.bankAccountNumber ?? '']
        .where((e) => e.trim().isNotEmpty).join('　');
    final issueDate = invoice.issueDate ?? InvoicePdfService._monthEnd(invoice);
    final subject = (settings?.invoiceSubject ?? '').trim();
    final workPeriod = InvoicePdfService._workPeriod(invoice);
    return Material(
      color: Colors.white,
      elevation: 2,
      child: SizedBox(
        width: 595, height: 842,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(37, 28, 37, 28),
          child: DefaultTextStyle(
            style: const TextStyle(color: Colors.black87, fontSize: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(height: 40, child: Stack(children: [
                const Align(alignment: Alignment.topCenter, child: Text('御　請　求　書',
                  style: TextStyle(color: blue,fontSize:17,fontWeight:FontWeight.w900,letterSpacing:4))),
                Align(alignment: Alignment.topRight, child: Column(crossAxisAlignment: CrossAxisAlignment.end,children:[
                  Text(InvoicePdfService._dateJa(issueDate),style:const TextStyle(fontSize:10)),
                  Text('請求書番号：${invoice.invoiceNumber}',style:const TextStyle(fontSize:8,color:blue)),
                ])),
              ])),
              Row(crossAxisAlignment: CrossAxisAlignment.start,children:[
                Expanded(child: Container(height:40,decoration:const BoxDecoration(border:Border(bottom:BorderSide(color:blue,width:1.4))),
                  child:Stack(alignment:Alignment.center,children:[
                    Text(invoice.customerId,style:const TextStyle(fontSize:17,fontWeight:FontWeight.w900)),
                    const Align(alignment:Alignment.centerRight,child:Text('御中',style:TextStyle(fontSize:10,color:blue,fontWeight:FontWeight.w900))),
                  ]))),
                const SizedBox(width:14),
                SizedBox(width:245,child:Stack(children:[
                  Padding(padding:const EdgeInsets.only(right:28),child:Column(crossAxisAlignment:CrossAxisAlignment.end,children:[
                    Text(settings?.companyName ?? '',style:const TextStyle(fontSize:13,fontWeight:FontWeight.w900)),
                    if((settings?.companyPostalCode??'').isNotEmpty) Text('〒${settings!.companyPostalCode}',style:const TextStyle(fontSize:7.5)),
                    if((settings?.companyAddress??'').isNotEmpty) Text(settings!.companyAddress,style:const TextStyle(fontSize:7.5)),
                    if((settings?.companyPhone??'').isNotEmpty) Text('TEL：${settings!.companyPhone}',style:const TextStyle(fontSize:7.5)),
                  ])),
                  Positioned(right:0,top:0,child:_ScreenSeal(companyName:settings?.companyName??'')),
                ])),
              ]),
              const SizedBox(height:2),
              Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Expanded(child:Container(padding:const EdgeInsets.all(8),decoration:BoxDecoration(border:Border.all(color:blue,width:1.1)),child:Column(children:[
                  Row(children:[const Text('御請求金額',style:TextStyle(color:blue,fontSize:13,fontWeight:FontWeight.w900)),const SizedBox(width:10),
                    Expanded(child:Container(height:34,alignment:Alignment.center,decoration:BoxDecoration(border:Border.all(color:blue)),
                      child:Text(InvoicePdfService._yen(invoice.grandTotalYen),style:const TextStyle(fontSize:20,fontWeight:FontWeight.w900))))]),
                  const SizedBox(height:5),
                  Text(bank.isEmpty?'振込先：請求書設定の口座情報':'振込先：$bank',style:const TextStyle(fontSize:9)),
                  if((settings?.bankAccountHolder??'').trim().isNotEmpty) Text('口座名義：${settings!.bankAccountHolder}',style:const TextStyle(fontSize:8)),
                  const Text('（振込手数料は御社にて御負担願います）',style:TextStyle(fontSize:7.5,color:blue)),
                ]))),
                const SizedBox(width:4),
                SizedBox(width:142,height:66,child:_ScreenApprovals(approvals:approvals)),
              ]),
              const SizedBox(height:3),
              const Text('下記の通り、御請求申し上げますので、お支払約定日までに、\n下記の口座宛にお振り込み頂きますよう宜しくお願い申し上げます。',
                style:TextStyle(fontSize:8.5,color:blue)),
              const SizedBox(height:10),
              Container(height:30,decoration:BoxDecoration(border:Border.all(color:blue,width:.8)),child:Row(children:[
                Container(width:92,alignment:Alignment.center,color:blue,child:const Text('件名 ／ 工期',style:TextStyle(color:Colors.white,fontSize:9,fontWeight:FontWeight.w900))),
                Expanded(child:Padding(padding:const EdgeInsets.symmetric(horizontal:7),child:Row(children:[
                  Expanded(child:Text(subject.isEmpty?'件名未設定':subject,style:const TextStyle(fontSize:8.5,fontWeight:FontWeight.w900))),
                  Text(workPeriod,style:const TextStyle(fontSize:8)),
                ]))),
              ])),
              const SizedBox(height:7),
              _ScreenDetailTable(rows:rows),
              const SizedBox(height:7),
              Align(alignment:Alignment.centerRight,child:SizedBox(width:315,child:Column(children:[
                _summary('計',invoice.subtotalYen),_summary('消費税',invoice.taxYen),_summary('合計(税込)',invoice.grandTotalYen,strong:true),
              ]))),
              const SizedBox(height:8),
              Container(height:39,decoration:BoxDecoration(border:Border.all(color:blue,width:.8)),child:Row(children:[
                Expanded(child:_contract('お支払約定日',(settings?.paymentDueText??'').trim().isEmpty?'未設定':settings!.paymentDueText)),
                Container(width:.8,color:blue),
                Expanded(child:_contract('金額',InvoicePdfService._yen(invoice.grandTotalYen),strong:true)),
              ])),
              const SizedBox(height:8),
              Container(height:60,padding:const EdgeInsets.all(7),decoration:BoxDecoration(border:Border.all(color:blue,width:.8)),
                child:Text('備考：${settings?.footerNote??''}',style:const TextStyle(fontSize:8))),
            ]),
          ),
        ),
      ),
    );
  }
  static Widget _summary(String label,int value,{bool strong=false})=>Container(height:25,decoration:BoxDecoration(border:Border.all(color:blue,width:.55)),child:Row(children:[
    Container(width:90,alignment:Alignment.center,color:blue,child:Text(label,style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w900))),
    Expanded(child:Padding(padding:const EdgeInsets.only(right:8),child:Text(InvoicePdfService._yen(value),textAlign:TextAlign.right,style:TextStyle(fontSize:strong?11:9,fontWeight:strong?FontWeight.w900:FontWeight.w500)))),
  ]));
  static Widget _contract(String label,String value,{bool strong=false})=>Row(children:[
    Container(width:92,alignment:Alignment.center,color:blue,child:Text(label,style:const TextStyle(color:Colors.white,fontSize:9,fontWeight:FontWeight.w900))),
    Expanded(child:Center(child:Text(value,style:TextStyle(fontSize:strong?12:9,fontWeight:strong?FontWeight.w900:FontWeight.w500)))),
  ]);
}
class _ScreenDetailTable extends StatelessWidget {
  const _ScreenDetailTable({required this.rows}); final List<_InvoiceFormRow> rows;
  @override Widget build(BuildContext context)=>Table(
    border:TableBorder.all(color:_ExactInvoiceScreen.blue,width:.55),
    columnWidths:const {0:FlexColumnWidth(2.15),1:FlexColumnWidth(2.05),2:FlexColumnWidth(.8),3:FlexColumnWidth(1.25),4:FlexColumnWidth(1.45)},
    children:[
      TableRow(decoration:const BoxDecoration(color:_ExactInvoiceScreen.blue),children:['作業所名','工事内容','数量','単価','請求金額'].map((e)=>_cell(e,white:true,center:true)).toList()),
      for(var i=0;i<rows.length;i++) TableRow(decoration:BoxDecoration(color:i.isOdd?_ExactInvoiceScreen.pale:Colors.white),children:[
        _cell(rows[i].siteName),_cell(rows[i].content),_cell(rows[i].quantity,right:true),_cell(rows[i].unitPrice,right:true),_cell(rows[i].amount,right:true),
      ]),
    ]);
  Widget _cell(String s,{bool right=false,bool center=false,bool white=false})=>Padding(padding:const EdgeInsets.symmetric(horizontal:4,vertical:2.5),child:Text(s,textAlign:center?TextAlign.center:right?TextAlign.right:TextAlign.left,maxLines:2,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:7,color:white?Colors.white:Colors.black87,fontWeight:white?FontWeight.w900:FontWeight.w500)));
}
class _ScreenSeal extends StatelessWidget {
 const _ScreenSeal({required this.companyName}); final String companyName;
 @override Widget build(BuildContext context)=>Container(width:34,height:34,alignment:Alignment.center,decoration:BoxDecoration(border:Border.all(color:const Color(0xffb33b32),width:1.4)),child:Text(companyName.length>4?companyName.substring(0,4):companyName,textAlign:TextAlign.center,maxLines:2,style:const TextStyle(fontSize:7,color:Color(0xffb33b32),fontWeight:FontWeight.w900)));
}
class _ScreenApprovals extends StatelessWidget {
 const _ScreenApprovals({required this.approvals}); final List<InvoiceApprovalRecord> approvals;
 @override Widget build(BuildContext context)=>Row(children:[for(var i=0;i<2;i++) Expanded(child:Container(decoration:BoxDecoration(border:Border.all(color:_ExactInvoiceScreen.blue,width:.72)),child:Column(children:[
  Container(height:17,alignment:Alignment.center,color:_ExactInvoiceScreen.blue,child:Text(i<approvals.length?approvals[i].name:'確認',maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:Colors.white,fontSize:7,fontWeight:FontWeight.w900))),
  Expanded(child:Center(child:Text(i<approvals.length&&approvals[i].approved?'承認済':'',style:const TextStyle(fontSize:7,fontWeight:FontWeight.w900)))),
 ])))]);
}
