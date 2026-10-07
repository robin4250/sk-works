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
            13 * PdfPageFormat.mm,
            10 * PdfPageFormat.mm,
            13 * PdfPageFormat.mm,
            10 * PdfPageFormat.mm,
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
    while (rows.length < 10) {
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
    final companyLogo = _memoryImage(settings?.companyLogoBase64 ?? '');

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
            pw.SizedBox(
              width: 245,
              child: pw.Stack(
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(right: 28),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.end,
                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                          children: [
                            if (companyLogo != null) ...[
                              pw.SizedBox(
                                width: 24,
                                height: 24,
                                child: pw.Image(companyLogo, fit: pw.BoxFit.contain),
                              ),
                              pw.SizedBox(width: 5),
                            ],
                            pw.Text(
                              settings?.companyName ?? '',
                              textAlign: pw.TextAlign.right,
                              style: pw.TextStyle(
                                fontSize: 13,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        if ((settings?.companyPostalCode ?? '').isNotEmpty)
                          pw.Text('〒${settings!.companyPostalCode}', textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 7.5)),
                        if ((settings?.companyAddress ?? '').isNotEmpty)
                          pw.Text(settings!.companyAddress, textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 7.5)),
                        if ((settings?.companyPhone ?? '').isNotEmpty)
                          pw.Text('TEL：${settings!.companyPhone}', textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 7.5)),
                        if ((settings?.companyFax ?? '').isNotEmpty)
                          pw.Text('FAX：${settings!.companyFax}', textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 7.5)),
                      ],
                    ),
                  ),
                  pw.Positioned(
                    right: -2,
                    top: -5,
                    child: _companySeal(settings?.companyName ?? ''),
                  ),
                ],
              ),
            ),
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

  static pw.Widget _approvalBoxes(
    List<InvoiceApprovalRecord> approvals,
    PdfColor blue,
  ) {
    final visible = approvals.take(2).toList();
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < 2; i++) ...[
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
                                  visible[i].name,
                                  visible[i].approvedAt ?? DateTime.now(),
                                  designB: visible[i].position.isEven,
                                )
                              : pw.Text(
                                  visible[i].name,
                                  textAlign: pw.TextAlign.center,
                                  style: pw.TextStyle(
                                    fontSize: 6.2,
                                    color: blue,
                                  ),
                                ),
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
    String name,
    DateTime date, {
    required bool designB,
  }) {
    final red = PdfColor.fromHex('#B83232');
    final label = _surnameForStamp(name);
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
            pw.Text(
              label,
              maxLines: 1,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                color: red,
                fontSize: 6.0,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _surnameForStamp(String name) {
    final value = name.trim();
    if (value.isEmpty) return '確認者';
    final parts = value.split(RegExp(r'\\s+')).where((part) => part.isNotEmpty);
    if (parts.length > 1) return parts.first;
    if (RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value) || value.length <= 2) {
      return value;
    }
    return value.substring(0, 2);
  }

  static pw.MemoryImage? _memoryImage(String encoded) {
    final value = encoded.trim();
    if (value.isEmpty) return null;
    try {
      return pw.MemoryImage(base64Decode(value));
    } catch (_) {
      return null;
    }
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
    return _InvoicePreviewData(pdfBytes: pdfBytes, settings: settings);
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
                        child: _InvoiceNativePreview(
                          invoices: widget.invoices,
                          settings: previewData.settings,
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
  });

  final Uint8List pdfBytes;
  final InvoiceSettingsData? settings;
}

class _InvoiceNativePreview extends StatelessWidget {
  const _InvoiceNativePreview({
    required this.invoices,
    required this.settings,
  });

  final List<InvoiceCalculationResult> invoices;
  final InvoiceSettingsData? settings;

  @override
  Widget build(BuildContext context) {
    final invoice = invoices.first;
    final rows = <_InvoiceNativeRowData>[];
    for (final site in invoice.siteCalculations) {
      for (final line in site.lines) {
        rows.add(
          _InvoiceNativeRowData(
            site: site.siteName,
            content: line.workContent?.trim().isNotEmpty == true
                ? line.workContent!
                : line.label,
            quantity: line.quantity,
            unitPrice: line.unitPriceYen,
            amount: line.amountYen,
          ),
        );
      }
    }
    while (rows.length < 10) {
      rows.add(const _InvoiceNativeRowData.empty());
    }

    final issueDate = invoice.issueDate;
    final issuer = settings?.companyName.trim() ?? '';
    final bank = [
      settings?.bankName ?? '',
      settings?.bankBranch ?? '',
      settings?.bankAccountType ?? '',
      settings?.bankAccountNumber ?? '',
    ].where((value) => value.trim().isNotEmpty).join('　');

    return Material(
      color: Colors.white,
      elevation: 3,
      child: SizedBox(
        width: 595,
        height: 842,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(34, 28, 34, 28),
          child: DefaultTextStyle(
            style: const TextStyle(color: Colors.black87, fontSize: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    const Text(
                      '請　求　書',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 5,
                      ),
                    ),
                    Align(
                      alignment: Alignment.topRight,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (issueDate != null) Text(_date(issueDate)),
                          Text('請求書番号：${invoice.invoiceNumber}'),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.only(bottom: 5),
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: Color(0xff3f6688),
                              width: 1.4,
                            ),
                          ),
                        ),
                        child: Text(
                          '${invoice.customerId}　御中',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 28),
                    SizedBox(
                      width: 220,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            issuer,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if ((settings?.companyPostalCode ?? '').isNotEmpty)
                            Text('〒${settings!.companyPostalCode}'),
                          if ((settings?.companyAddress ?? '').isNotEmpty)
                            Text(settings!.companyAddress),
                          if ((settings?.companyPhone ?? '').isNotEmpty)
                            Text('TEL ${settings!.companyPhone}'),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Container(
                        height: 52,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        alignment: Alignment.centerLeft,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: const Color(0xff3f6688),
                            width: 1.3,
                          ),
                        ),
                        child: Text(
                          'ご請求金額　¥${_money(invoice.grandTotalYen)}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 18),
                    SizedBox(
                      width: 220,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if ((settings?.invoiceSubject ?? '').trim().isNotEmpty)
                            Text('件名：${settings!.invoiceSubject}'),
                          Text('対象期間：${invoice.billingPeriod}'),
                          if ((settings?.paymentDueText ?? '').trim().isNotEmpty)
                            Text('お支払条件：${settings!.paymentDueText}'),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const _InvoiceNativeHeader(),
                ...rows.map((row) => _InvoiceNativeLine(data: row)),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '振込先',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 4),
                          Text(bank.isEmpty ? '振込先未設定' : bank),
                          if ((settings?.bankAccountHolder ?? '').isNotEmpty)
                            Text('口座名義　${settings!.bankAccountHolder}'),
                          const SizedBox(height: 10),
                          if ((settings?.footerNote ?? '').trim().isNotEmpty)
                            Text(settings!.footerNote),
                        ],
                      ),
                    ),
                    const SizedBox(width: 18),
                    SizedBox(
                      width: 230,
                      child: Column(
                        children: [
                          _totalRow('小計', invoice.subtotalYen),
                          _totalRow('消費税', invoice.taxYen),
                          _totalRow('合計', invoice.grandTotalYen, bold: true),
                        ],
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                const Divider(),
                Text(
                  '※ 画面プレビューと印刷・共有は同じ請求データを使用しています。',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 8, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _totalRow(String label, int amount, {bool bold = false}) =>
      Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.black26)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
                ),
              ),
            ),
            Text(
              '¥${_money(amount)}',
              style: TextStyle(
                fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
              ),
            ),
          ],
        ),
      );

  static String _date(DateTime value) =>
      '${value.year}年${value.month}月${value.day}日';

  static String _money(num value) {
    final digits = value.round().toString();
    return digits.replaceAllMapped(
      RegExp(r'(?<=\\d)(?=(\\d{3})+(?!\\d))'),
      (_) => ',',
    );
  }
}

class _InvoiceNativeRowData {
  const _InvoiceNativeRowData({
    required this.site,
    required this.content,
    required this.quantity,
    required this.unitPrice,
    required this.amount,
  });

  const _InvoiceNativeRowData.empty()
      : site = '',
        content = '',
        quantity = 0,
        unitPrice = 0,
        amount = 0;

  final String site;
  final String content;
  final num quantity;
  final int unitPrice;
  final int amount;
}

class _InvoiceNativeHeader extends StatelessWidget {
  const _InvoiceNativeHeader();

  @override
  Widget build(BuildContext context) => Container(
        height: 30,
        decoration: BoxDecoration(
          color: const Color(0xffe8eef3),
          border: Border.all(color: const Color(0xff6f879a)),
        ),
        child: const Row(
          children: [
            Expanded(flex: 3, child: _InvoiceNativeCell('作業所名', bold: true)),
            Expanded(flex: 3, child: _InvoiceNativeCell('工事内容', bold: true)),
            Expanded(child: _InvoiceNativeCell('数量', bold: true, center: true)),
            Expanded(child: _InvoiceNativeCell('単価', bold: true, center: true)),
            Expanded(
              flex: 2,
              child: _InvoiceNativeCell('請求金額', bold: true, center: true),
            ),
          ],
        ),
      );
}

class _InvoiceNativeLine extends StatelessWidget {
  const _InvoiceNativeLine({required this.data});

  final _InvoiceNativeRowData data;

  @override
  Widget build(BuildContext context) => Container(
        height: 29,
        decoration: const BoxDecoration(
          border: Border(
            left: BorderSide(color: Color(0xffaebbc5)),
            right: BorderSide(color: Color(0xffaebbc5)),
            bottom: BorderSide(color: Color(0xffaebbc5)),
          ),
        ),
        child: Row(
          children: [
            Expanded(flex: 3, child: _InvoiceNativeCell(data.site)),
            Expanded(flex: 3, child: _InvoiceNativeCell(data.content)),
            Expanded(
              child: _InvoiceNativeCell(
                data.site.isEmpty ? '' : _quantity(data.quantity),
                right: true,
              ),
            ),
            Expanded(
              child: _InvoiceNativeCell(
                data.site.isEmpty
                    ? ''
                    : _InvoiceNativePreview._money(data.unitPrice),
                right: true,
              ),
            ),
            Expanded(
              flex: 2,
              child: _InvoiceNativeCell(
                data.site.isEmpty ? '' : _InvoiceNativePreview._money(data.amount),
                right: true,
              ),
            ),
          ],
        ),
      );

  static String _quantity(num value) =>
      value == value.roundToDouble() ? value.round().toString() : value.toString();
}

class _InvoiceNativeCell extends StatelessWidget {
  const _InvoiceNativeCell(
    this.text, {
    this.bold = false,
    this.right = false,
    this.center = false,
  });

  final String text;
  final bool bold;
  final bool right;
  final bool center;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        alignment: center
            ? Alignment.center
            : right
                ? Alignment.centerRight
                : Alignment.centerLeft,
        child: Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 8.5,
            height: 1.05,
            fontWeight: bold ? FontWeight.w900 : FontWeight.w500,
          ),
        ),
      );
}
