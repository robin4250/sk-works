import '../shared/trade_document_form_session.dart';
import '../shared/trade_document_form_renderer.dart';
import '../shared/trade_document_output_page.dart';
import '../shared/trade_document_confirmation_dialog.dart';
import '../shared/trade_document_actor_boundary.dart';
import '../shared/document_display_totals.dart';
import '../shared/trade_document_attachment.dart';
import '../shared/trade_document_attachment_repository.dart';
import '../shared/trade_document_attachment_editor_page.dart';
import 'invoice_order_acceptance_pdf.dart';
import 'invoice_acceptance_resolver.dart';
import 'invoice_acceptance_workspace_guard.dart';
import 'invoice_acceptance_notice.dart';
import '../expenses/expense_document_repository.dart';
import '../expenses/expense_detail_pdf.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../data/supabase_backend.dart';
import '../../domain/invoice_engine.dart';
import '../../international/language_controller.dart';
import '../shared/company_seal_pdf.dart';
import 'invoice_approval_repository.dart';
import 'invoice_approval_entry_actions.dart';
import 'invoice_notice_candidate_rpc.dart';
import 'invoice_preview_raster.dart';
import 'invoice_preview_failure.dart';
import 'invoice_native_pdf_view.dart';
import '../shared/financial_preview_chrome.dart';
import 'invoice_stamp_surname_dialog.dart';
import 'invoice_settings_repository.dart';
import '../shared/r33_input.dart';

class InvoicePdfService {
  const InvoicePdfService._();

  /// Preserve the approved body fonts when available; offline output uses the
  /// bundled Japanese font instead of failing the entire invoice preview.
  static Future<pw.Font> loadBodyFont(Future<pw.Font> Function() fetch) async {
    try {
      return await fetch().timeout(const Duration(seconds: 8));
    } catch (_) {
      return CompanySealPdf.loadFont();
    }
  }

  static Future<Uint8List> buildPdf(
    List<InvoiceCalculationResult> invoices, {
    Map<String, ExpenseDocumentDetails>? expenseDetailsByInvoice,
    Map<String, TradeDocumentAttachment?>? acceptanceByInvoice,
    VoidCallback? onMissingLockedAcceptance,
    String? title,
    InvoiceSettingsData? settings,
    PdfPageFormat format = PdfPageFormat.a4,
    pw.Font? regularFont,
    pw.Font? boldFont,
    Map<String, List<InvoiceApprovalRecord>>? approvalsByInvoice,
    bool allowLegacyApprovalInitialization = true,
  }) async {
    final lease = TradeDocumentActorLease();
    try {
    if (invoices.isEmpty) {
      throw ArgumentError.value(invoices, 'invoices', 'must not be empty');
    }
    for (final invoice in invoices) {
      if (invoice.outputReadinessError != null) {
        throw StateError(invoice.outputReadinessError!);
      }
    }
    final approvalRepository = InvoiceApprovalRepository.maybeCreate();
    if (!allowLegacyApprovalInitialization && approvalRepository == null &&
        invoices.any((invoice) => invoice.invoiceId.isNotEmpty &&
            approvalsByInvoice?.containsKey(invoice.invoiceId) != true)) {
      throw StateError(SkoLanguageController.tr(
        '承認情報を確認できません。請求書を再読み込みしてください。',
      ));
    }
    final effectiveSettings = settings ?? await _loadSettings();

    final regular = regularFont ?? await loadBodyFont(PdfGoogleFonts.notoSansJPRegular);
    final bold = boldFont ?? await loadBodyFont(PdfGoogleFonts.notoSansJPBold);
    final document = pw.Document(
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );
    for (final invoice in invoices) {
      final attachmentRepository = TradeDocumentAttachmentRepository.maybeCreate();
      final hasExplicitAcceptance =
          acceptanceByInvoice?.containsKey(invoice.invoiceId) == true;
      final loadAcceptanceWorkspace = InvoiceAcceptanceWorkspaceGuard.shouldLoad(
        invoiceId: invoice.invoiceId,
        sourceRevision: invoice.documentUpdatedAt,
        hasExplicitSelection: hasExplicitAcceptance,
        repositoryAvailable: attachmentRepository != null,
      );
      final acceptance = hasExplicitAcceptance
          ? acceptanceByInvoice![invoice.invoiceId]
          : !loadAcceptanceWorkspace
          ? null
          : InvoiceAcceptanceResolver.resolve(
              await attachmentRepository!.loadWorkspace(
                subjectKind: 'invoice', subjectId: invoice.invoiceId,
                sourceRevision: DateTime.parse(invoice.documentUpdatedAt!).toUtc().toIso8601String()),
              issueDate: invoice.issueDate,
              parentSealSnapshot: invoice.companySealSnapshot,
              parentSealEnabled: effectiveSettings?.companySealEnabled != false,
              onMissingLockedAcceptance: onMissingLockedAcceptance,
            );
      final expenses = expenseDetailsByInvoice?[invoice.invoiceId] ?? (invoice.periodStart == null ? null : await ExpenseDocumentRepository.load(ExpenseDocument.invoice, invoice.invoiceId, invoice.periodStart!, updatedAt:invoice.documentUpdatedAt));
      if (invoice.expenseCost.isCurrent && expenses?.costRecoveryAmountYen != invoice.expenseExtraAmountYen) {
        throw StateError('別途経費の内訳と請求書金額が一致しません。再読み込みしてください。');
      }
      if (expenses != null) {
        invoice.expenseCost.verifyDetails(expenses.claims.entries.map((claim) => {
          'id': claim.id, 'revision': claim.revision, 'amount_yen': claim.amountYen,
        }));
      }
      final sealFont = effectiveSettings?.companySealEnabled == false
          ? regular
          : await CompanySealPdf.loadStyleFont(invoice.companySealSnapshot.style);
      List<InvoiceApprovalRecord> approvals = const [];
      if (approvalsByInvoice?.containsKey(invoice.invoiceId) == true) {
        approvals = List<InvoiceApprovalRecord>.unmodifiable(
          approvalsByInvoice![invoice.invoiceId]!,
        );
      } else if (approvalRepository != null && invoice.invoiceId.isNotEmpty) {
        try {
          approvals = await approvalRepository.loadForInvoice(
            invoice.invoiceId,
            allowLegacyInitialization: allowLegacyApprovalInitialization,
          );
        } on InvoiceStampSurnameReadException {
          rethrow;
        } catch (_) {
          if (!allowLegacyApprovalInitialization) rethrow;
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
            build: (context) => _sheet(
              invoice,
              effectiveSettings,
              approvals,
              context: context,
              companyFont: bold,
              sealFont: sealFont,
              fallbackFont: regular,
              pageIndex: pageIndex,
              pageCount: pageCount,
            ),
          ),
        );
      }
      // Keep every invoice detail page together. Its contract and terms follow
      // the invoice as one appendix; a single-page invoice starts it on page 2.
      if (acceptance != null) {
        await InvoiceOrderAcceptancePdf.append(document, acceptance,
          regularFont: regular, boldFont: bold);
      }
      if (expenses != null) {
        ExpenseDetailPdf.append(document, claims:expenses.claims, kind:ExpenseDocument.invoice, subjectId:expenses.subjectId, regularFont:regular, boldFont:bold, costRecoveryAmountYen:expenses.costRecoveryAmountYen);
      }
    }
    final bytes = await document.save();
    lease.verify();
    return bytes;
    } finally { lease.dispose(); }
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
    final lease = TradeDocumentActorLease();
    try {
    final bytes = await buildPdf(invoices, title: title, settings: settings);
    lease.verify();
    return await Printing.sharePdf(
      bytes: bytes,
      filename: fileNameFor(invoices, title: title),
      subject: subject,
      body: body,
    );
    } finally { lease.dispose(); }
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
      if (invoice.customerPostalCode.trim().isNotEmpty) {
        buffer.writeln('〒${invoice.customerPostalCode}');
      }
      if (invoice.customerAddress.trim().isNotEmpty) {
        buffer.writeln(invoice.customerAddress);
      }
      if (invoice.customerPhone.trim().isNotEmpty) {
        buffer.writeln('TEL ${invoice.customerPhone}');
      }
      for (final site in invoice.siteCalculations) {
        buffer.writeln(site.siteName);
        for (final line in site.lines.where((line) => !isInvoiceChargeLine(line))) {
          buffer.writeln(
            '${_displayLineLabel(line, site)} ${_quantity(line.quantity)} × '
            '${_visibleYen(line.unitPriceYen)} = ${_visibleYen(line.amountYen)}',
          );
        }
        if (site.manualAdjustmentYen != 0) {
          buffer.writeln('値引き・調整 ${_yen(site.manualAdjustmentYen)}');
        }
      }
      if (invoice.expenseExtraAmountYen != 0) {
        buffer.writeln('別途経費（原額） ${_yen(invoice.expenseExtraAmountYen)}');
      }
      final totals = DocumentDisplayTotals.invoice(invoice);
      for (final item in invoice.documentAdjustments.where((item) => item.isFinalAmount)) {
        buffer.writeln('${item.title}（追加税なし） ${_yen(item.signedYen)}');
      }
      buffer
        ..writeln('小計 ${_visibleYen(totals.workSubtotal)}')
        ..writeln('福利厚生費 ${_visibleYen(totals.welfare)}')
        ..writeln('消費税 ${_visibleYen(invoice.taxYen)}')
        ..writeln('合計(税込) ${_visibleYen(invoice.grandTotalYen)}')
        ..writeln('請求合計 ${_visibleYen(invoice.grandTotalYen)}');
    }
    return buffer.toString();
  }

  static bool _isWelfareLine(InvoiceLine line) {
    final label = line.displayWorkContent.replaceAll(RegExp(r'[（）()\s]'), '');
    return line.category == 'welfare' || label == '法定福利費' || label == '福利厚生費';
  }

  static String _welfareLabel(int rateBps) =>
      rateBps > 0 ? '福利厚生費（${_quantity(rateBps / 100)}%）' : '福利厚生費';

  static String _displayLineLabel(
    InvoiceLine line,
    SiteInvoiceCalculation site,
  ) => _isWelfareLine(line)
      ? _welfareLabel(site.welfareRateBps)
      : line.displayWorkContent.trim();

  // Adopted invoice v8 uses absolute A4 coordinates in PDF points.
  static List<_InvoiceFormRow> _detailRows(InvoiceCalculationResult invoice) {
    final rows = <_InvoiceFormRow>[];
    for (final site in invoice.siteCalculations) {
      final details = site.lines.where((line) => !isInvoiceChargeLine(line)).toList();
      for (var i = 0; i < details.length; i++) {
        final line = details[i];
        rows.add(
          _InvoiceFormRow(
            siteName: line.siteLabel.trim().isNotEmpty
                ? line.siteLabel
                : (i == 0 ? site.siteName : '〃'),
            content: _displayLineLabel(line, site),
            quantity: line.quantity == 0 ? '' : _quantity(line.quantity),
            unitPrice: _isWelfareLine(line)
                ? '${_quantity(site.welfareRateBps / 100)}%'
                : (line.unitPriceText ?? '').trim().isNotEmpty
                ? _visiblePriceText(line.unitPriceText!)
                : _visibleNumber(line.unitPriceYen),
            amount: _visibleNumber(line.amountYen),
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
    if (invoice.expenseExtraAmountYen != 0) {
      rows.add(_InvoiceFormRow(
        siteName: '経費',
        content: '別途経費（原額）',
        quantity: '',
        unitPrice: '',
        amount: _number(invoice.expenseExtraAmountYen),
      ));
    }
    for (final item in invoice.documentAdjustments.where((item) => item.isFinalAmount)) {
      rows.add(_InvoiceFormRow(siteName: '調整', content: '${item.title}（追加税なし）',
        quantity: '', unitPrice: '', amount: _number(item.signedYen)));
    }
    return rows;
  }

  static pw.Widget _sheet(
    InvoiceCalculationResult invoice,
    InvoiceSettingsData? settings,
    List<InvoiceApprovalRecord> approvals, {
    required pw.Context context,
    required pw.Font companyFont,
    required pw.Font sealFont,
    required pw.Font fallbackFont,
    int pageIndex = 0,
    int pageCount = 1,
  }) {
    final blue = PdfColor.fromHex('#138BE1');
    final ink = PdfColor.fromHex('#12377C');
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
      double letterSpacing = 0,
      double wordSpacing = 1,
      double lineSpacing = 0,
      double? baseline,
      bool softWrap = true,
    }) {
      children.add(
        pw.Positioned(
          // PDF text layout includes two trailing character-spacing advances;
          // compensate aligned spans so their visible edge matches the reference.
          left:
              x +
              (align == pw.TextAlign.right
                  ? 2 * letterSpacing
                  : align == pw.TextAlign.center
                  ? letterSpacing
                  : 0),
          // Noto Sans JP ascender is 1.16 em; align text to adopted baselines.
          top: baseline == null ? y - size * .30 : baseline - size * 1.16,
          child: pw.SizedBox(
            width: w,
            height: h,
            child: pw.Text(
              value,
              textAlign: align,
              maxLines: maxLines,
              softWrap: softWrap,
              style: pw.TextStyle(
                fontSize: size,
                letterSpacing: letterSpacing,
                wordSpacing: wordSpacing,
                lineSpacing: lineSpacing,
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
      '請　求　書'.replaceAll('　', ''),
      222.64,
      28,
      150,
      size: 20,
      bold: true,
      letterSpacing: 20,
      maxLines: 1,
      softWrap: false,
      baseline: 46,
      align: pw.TextAlign.center,
      h: 30,
    );
    line(222.64, 55, 150, 0, color: blue, width: .55);
    text(
      'I N V O I C E',
      222.64,
      62,
      150,
      size: 7,
      wordSpacing: 1.2551,
      color: blue,
      align: pw.TextAlign.center,
    );
    text('請求書番号', 450.3, 32, 65);
    text(
      invoice.invoiceNumber,
      510,
      32,
      57.2756,
      letterSpacing: .816,
      align: pw.TextAlign.right,
    );
    text('発行日', 450.3, 47, 50);
    text(
      _dateJa(invoice.issueDate ?? _monthEnd(invoice)),
      490,
      47,
      77.2756,
      letterSpacing: .633,
      align: pw.TextAlign.right,
    );
    box(28, 80, 266, 96);
    box(28, 80, 266, 20, fill: pale, radius: 0, line: .3);
    text('御 請 求 先', 38, 86, 246, size: 9, bold: true, color: blue);
    text(
      '${invoice.customerId} 御中',
      38,
      111,
      246,
      size: 11,
      bold: true,
      baseline: 122,
      h: 23,
    );
    if (invoice.customerPostalCode.trim().isNotEmpty) {
      text('〒${invoice.customerPostalCode}', 38, 133, 246, letterSpacing: .64);
    }
    final hasCustomerPhone = invoice.customerPhone.trim().isNotEmpty;
    if (invoice.customerAddress.trim().isNotEmpty) {
      if (hasCustomerPhone) {
        text(
          invoice.customerAddress,
          38,
          146,
          246,
          size: 6.5,
          h: 23,
          lineSpacing: 1.588,
        );
      } else {
        text(invoice.customerAddress, 38, 148, 246, h: 30, lineSpacing: 4.864);
      }
    }
    if (hasCustomerPhone) {
      text(
        'TEL ${invoice.customerPhone}',
        38,
        168,
        246,
        size: 6,
        h: 10,
        maxLines: 1,
      );
    }
    box(316, 80, right - 316, 55);
    box(316, 80, 104, 31, fill: blue, radius: 0, line: .3);
    box(316, 111, 104, 24, fill: pale, radius: 0, line: .3);
    text('ご請求金額（税込）', 332, 92, 86, size: 8, bold: true, color: PdfColors.white);
    text(
      _visibleYen(invoice.grandTotalYen),
      424,
      86,
      131.2756,
      size: 18,
      letterSpacing: 1.916,
      baseline: 103,
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
      letterSpacing: .723,
      align: pw.TextAlign.right,
    );
    box(316, 143, right - 316, 88);
    text('　お振込先', 330, 156, 220, size: 9, bold: true, color: blue);
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
      text(
        bankValues[i],
        418,
        174 + i * 11,
        137,
        size: 6.1,
        letterSpacing: i == 3 ? .805 : 0,
      );
    }
    if (bankValues.every((v) => v.trim().isEmpty)) {
      text('未登録', 418, 174, 137, size: 6.1, color: PdfColors.red);
    }
    box(28, 186, 266, 20);
    text('件名', 40, 194, 45);
    text(settings?.invoiceSubject ?? '', 90, 193, 196, size: 8, bold: true);
    box(28, 214, 266, 20);
    text('工期', 40, 222, 45);
    text(_workPeriod(invoice), 90, 222, 196, letterSpacing: .4);
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
        // Use geometry, not collapsible whitespace, for the ditto inset.
        final siteDittoIndent =
            col == 1 && values[col].trimLeft().startsWith('〃')
            ? 5.5 * 5.4
            : 0.0;
        text(
          values[col],
          xs[col] + 3 + siteDittoIndent,
          y + 3,
          xs[col + 1] - xs[col] - 6 - siteDittoIndent,
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
    final display = DocumentDisplayTotals.invoice(invoice);
    final totals = [display.workSubtotal, display.welfare, display.tax, display.total];
    final labels = [
      '小計',
      '福利厚生費',
      invoice.taxRateBps == 0
          ? '消費税'
          : '消費税（${_quantity(invoice.taxRateBps / 100)}%）',
      'ご請求金額（税込）',
    ];
    for (var i = 0; i < 4; i++) {
      text(
        labels[i],
        354,
        679 + i * 15,
        100,
        size: 6.5,
        color: i == 3 ? blue : ink,
      );
      text(
        i == 3 ? _visibleYen(totals[i]) : _visibleNumber(totals[i]),
        453,
        679 + i * 15,
        104.2756,
        size: i == 3 ? 11 : 7.5,
        letterSpacing: (i == 3 ? 11 : 7.5) * .1065,
        baseline: 687 + i * 15,
        bold: i == 3,
        align: pw.TextAlign.right,
        h: 15,
      );
    }
    box(28, 744.8898, right - 28, 70);
    line(377.2756, 749.8898, 0, 60);
    text(
      invoice.companySealSnapshot.registeredName(settings?.companyName ?? ''),
      50,
      756,
      285,
      size: 11,
      bold: true,
      color: PdfColors.black,
      baseline: 766.8898,
      align: pw.TextAlign.center,
      h: 23,
    );
    text(
      '${(settings?.companyPostalCode ?? '').isEmpty ? '' : '〒${settings!.companyPostalCode} '}${settings?.companyAddress ?? ''}',
      50,
      784,
      285,
      size: 6,
      letterSpacing: .21,
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
      letterSpacing: .22,
      wordSpacing: 4.4642857,
      align: pw.TextAlign.center,
    );
    // Attach the seal to the actual registered company name using the same
    // bold font and size as the centered footer label. Keep the adopted
    // overlap and footer geometry for every company, not only the sample.
    final companyNameWidth =
        (companyFont
                    .getFont(context)
                    .stringMetrics(invoice.companySealSnapshot.registeredName(
                        settings?.companyName ?? ''))
                    .advanceWidth *
                11)
            .clamp(0.0, 285.0)
            .toDouble();
    final companySealLeft = 50 + 285 / 2 + companyNameWidth / 2 - 11.8622;
    if (settings?.companySealEnabled != false) {
      children.add(
        pw.Positioned(
          left: companySealLeft,
          top: 750.6701,
          child: pw.SizedBox(
            width: 42,
            height: 40.4394,
            child: pw.FittedBox(
              fit: pw.BoxFit.fill,
              child: CompanySealPdf.build(
                invoice.companySealSnapshot.registeredName(
                    settings?.companyName ?? ''),
                style: invoice.companySealSnapshot.style,
                companyId: invoice.companySealSnapshot.companyId, uploadedPng: invoice.companySealSnapshot.uploadedPng,
                font: sealFont,
                fallbackFont: fallbackFont,
              ),
            ),
          ),
        ),
      );
    }
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
    return pw.Container(
      color: PdfColors.white,
      child: pw.Stack(children: children),
    );
  }

  static pw.Widget _datedApprovalStamp(InvoiceApprovalRecord record) {
    final red = PdfColor.fromHex('#D9272E');
    final surname = record.stampSurname;
    if (surname == null || surname.isEmpty) return _legacyApprovalStamp(record);
    return pw.Container(
      width: 36,
      height: 36,
      padding: const pw.EdgeInsets.all(4),
      decoration: pw.BoxDecoration(
        shape: pw.BoxShape.circle,
        border: pw.Border.all(color: red, width: 1.5),
      ),
      child: pw.Center(
        child: pw.FittedBox(
          fit: pw.BoxFit.scaleDown,
          child: pw.Text(
            surname,
            style: pw.TextStyle(
              color: red,
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  static pw.Widget _legacyApprovalStamp(InvoiceApprovalRecord record) {
    final red = PdfColor.fromHex('#D9272E');
    final date = record.stampDisplayDate;
    final surname = _legacySurname(record.name);
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

  static String _legacySurname(String name) {
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
        '　-　${end.year}年${end.month}月${end.day}日';
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
    if (value == 0) return '';
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  static String _visibleNumber(int value) => value == 0 ? '' : _number(value);

  static String _visibleYen(int value) => value == 0 ? '' : _yen(value);

  static String _visiblePriceText(String value) {
    final parsed = num.tryParse(
      value.trim().replaceAll(RegExp(r'[,¥￥\s]'), ''),
    );
    return parsed == 0 ? '' : value;
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
    this.additionalActions = const [],
    this.allowLegacyApprovalInitialization = true,
    this.approvalFromNotification = false,
    this.approvalNotificationId,
  });

  final List<InvoiceCalculationResult> invoices;
  final String? title;
  final List<Widget> additionalActions;
  final bool allowLegacyApprovalInitialization;
  final bool approvalFromNotification;
  final String? approvalNotificationId;

  @override
  State<InvoicePdfPreviewPage> createState() => _InvoicePdfPreviewPageState();
}

class _InvoicePdfPreviewPageState extends State<InvoicePdfPreviewPage> {
  final _approvalRepository = InvoiceApprovalRepository.maybeCreate();
  late Future<_InvoicePreviewData> _previewData;
  int _previewRevision = 0;
  bool _approving = false;
  bool _openingAcceptance = false;
  TradeDocumentFormSession? _formScope;
  String get _formTarget=>'${_singleInvoice?.invoiceId}/${_singleInvoice?.documentUpdatedAt}';
  Future<void> _readyForm()async{if(_formScope==null)throw StateError('請求書を開き直してください。');await _formScope!.ready();_formScope!.requireScope();}
  Future<void> _formOutput()async{
    if(_openingAcceptance||_singleInvoice==null)return;setState(()=>_openingAcceptance=true);
    try{await _readyForm();final invoice=_singleInvoice!,pending=_previewData,data=await pending;_formScope!.requireScope();
      if(!identical(pending,_previewData))throw StateError('請求書を開き直してください。');
      final repo=TradeDocumentAttachmentRepository(SupabaseBackend.client,session:_formScope);
      final workspace=await repo.loadWorkspace(subjectKind:'invoice',subjectId:invoice.invoiceId,sourceRevision:DateTime.parse(invoice.documentUpdatedAt!).toUtc().toIso8601String());
      _formScope!.requireScope();final attachment=InvoiceAcceptanceResolver.resolve(workspace,issueDate:invoice.issueDate,parentSealSnapshot:invoice.companySealSnapshot,parentSealEnabled:data.settings?.companySealEnabled!=false);
      if(attachment==null)throw StateError('請書は作成されていません。');
      final bytes=await TradeDocumentFormRenderer.canonical(attachment.payload);_formScope!.requireScope();
      if(!mounted)return;await Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>TradeDocumentOutputPage(payload:attachment.payload,canonicalBytes:bytes,requireScope:_formScope!.requireScope,scopeChanges:_formScope)));
    }catch(error){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(error.toString())));}
    finally{if(mounted)setState(()=>_openingAcceptance=false);}
  }
  final _actorLease = TradeDocumentActorLease();
  // OFF until the server readiness receipt, grants and production tests pass.
  late final _noticeController = invoiceNoticeApprovalReleased && SupabaseBackend.isInitialized
      ? createInvoiceNoticeCandidateController(client: SupabaseBackend.client,
          enabled: invoiceNoticeApprovalReleased,
          invoiceId: _singleInvoice?.invoiceId ?? '',
          sourceRevision: _singleInvoice?.documentUpdatedAt ?? '')
      : null;

  @override
  void dispose() { _formScope?.dispose();_noticeController?.dispose(); _actorLease.dispose(); super.dispose(); }

  @override
  void initState() {
    super.initState();
    try{if(SupabaseBackend.isInitialized)_formScope=TradeDocumentFormSession(SupabaseBackend.client,target:_formTarget,currentTarget:()=>_formTarget);}catch(_){}
    _previewData = _buildPreviewData().timeout(
      const Duration(seconds: 90),
      onTimeout: () => throw StateError(SkoLanguageController.tr('請求書の読み込みに時間がかかっています。通信を確認して再試行してください。')),
    );
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
    var missingAcceptanceCount = 0;
    final pdfBytes = await InvoicePdfService.buildPdf(
      widget.invoices,
      title: widget.title,
      settings: settings,
      allowLegacyApprovalInitialization: widget.allowLegacyApprovalInitialization,
      onMissingLockedAcceptance: () { missingAcceptanceCount++; },
    );
    if (pdfBytes.isEmpty) {
      throw StateError('PDFデータが空です。');
    }
    final approvals = await _loadApprovals();
    return _InvoicePreviewData(
      pdfBytes: pdfBytes,
      settings: settings,
      approvals: approvals,
      missingAcceptanceCount: missingAcceptanceCount,
    );
  }

  Future<List<InvoiceApprovalRecord>> _loadApprovals() async {
    final invoice = _singleInvoice;
    final repository = _approvalRepository;
    if (invoice == null || invoice.invoiceId.isEmpty) return const [];
    if (repository == null) {
      if (!widget.allowLegacyApprovalInitialization) {
        throw StateError(SkoLanguageController.tr(
          '承認情報を確認できません。請求書を再読み込みしてください。',
        ));
      }
      return const [];
    }
    try {
      return await repository.loadForInvoice(invoice.invoiceId,
        allowLegacyInitialization: widget.allowLegacyApprovalInitialization);
    } on InvoiceStampSurnameReadException {
      rethrow;
    } catch (_) {
      if (!widget.allowLegacyApprovalInitialization) rethrow;
      return const [];
    }
  }

  Future<void> _setApprovalSurname() async {
    if (_approving) return;
    final invoice = _singleInvoice;
    final repository = _approvalRepository;
    if (invoice == null || repository == null) return;
    final actor = SupabaseBackend.isInitialized
        ? SupabaseBackend.client.auth.currentUser?.id : null;
    if (actor == null) return;
    void checkActor() {
      if (!SupabaseBackend.isInitialized ||
          SupabaseBackend.client.auth.currentUser?.id != actor) {
        throw StateError(SkoLanguageController.isEnglish
            ? 'Your account changed. Reopen this invoice before continuing.'
            : 'アカウントが変わりました。請求書を開き直してください。');
      }
    }
    setState(() => _approving = true);
    try {
      checkActor();
      final rows = await repository.loadForInvoice(invoice.invoiceId,
        allowLegacyInitialization: widget.allowLegacyApprovalInitialization);
      checkActor();
      final editable = rows.where((row) => row.canCurrentUserSetStampSurname).toList();
      if (!mounted) return;
      if (editable.length != 1) {
        throw StateError(SkoLanguageController.isEnglish
            ? 'Your approval-seal settings are unavailable. Reload the invoice.'
            : '本人の承認印設定を確認できません。請求書を再読み込みしてください。');
      }
      final saved = await editInvoiceStampSurname(context, repository, invoice.invoiceId,
        initialSurname: editable.single.draftStampSurname, checkActor: checkActor,
      );
      checkActor();
      if (!saved || !mounted) return;
      setState(() {
        _previewRevision++;
        _previewData = _buildPreviewData().timeout(const Duration(seconds: 90));
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          error is StateError ? error.message.toString()
              : (SkoLanguageController.isEnglish ? 'Could not update your seal surname. Check the pending approval and retry.' : '承認印の名字を更新できませんでした。承認待ち状態を確認して再試行してください。'),
        )));
      }
    } finally {
      if (mounted) setState(() => _approving = false);
    }
  }

  Future<void> _approve() async {
    if (_approving) return;
    final invoice = _singleInvoice;
    final repository = _approvalRepository;
    if (invoice == null || repository == null || invoice.invoiceId.isEmpty) {
      return;
    }
    final actor = SupabaseBackend.isInitialized
        ? SupabaseBackend.client.auth.currentUser?.id : null;
    if (actor == null) return;
    void checkActor() {
      if (!SupabaseBackend.isInitialized ||
          SupabaseBackend.client.auth.currentUser?.id != actor) {
        throw StateError(SkoLanguageController.isEnglish
            ? 'Your account changed. Reopen this invoice before continuing.'
            : 'アカウントが変わりました。請求書を開き直してください。');
      }
    }
    setState(() => _approving = true);
    try {
      checkActor();
      final rows = await repository.loadForInvoice(invoice.invoiceId,
        allowLegacyInitialization: widget.allowLegacyApprovalInitialization);
      checkActor();
      if (!mounted) return;
      final ownPending = rows.where((row) => row.canCurrentUserApprove).toList();
      if (ownPending.length != 1) {
        throw StateError(SkoLanguageController.isEnglish
            ? 'Your approval status has changed. Reload the invoice and check your approval permissions.'
            : '本人の承認状態が変わっています。請求書を再読み込みし、承認権限を確認してください。');
      }
      final row = ownPending.single;
      if (row.canCurrentUserSetStampSurname && row.draftStampSurname == null) {
        final saved = await editInvoiceStampSurname(context, repository, invoice.invoiceId, checkActor: checkActor);
        checkActor();
      if (!saved || !mounted) return;
      }
      checkActor();
      if (!mounted) return;
      final outcome = await openTradeDocumentConfirmation(context,
        kind: 'invoice', parentId: invoice.invoiceId,
        sourceRevision: invoice.documentUpdatedAt == null ? ''
          : DateTime.parse(invoice.documentUpdatedAt!).toUtc().toIso8601String());
      checkActor();
      if (!mounted || outcome == TradeConfirmationFlowOutcome.cancelled) return;
      final approved = outcome == TradeConfirmationFlowOutcome.confirmed ||
        await repository.approve(invoice.invoiceId);
      checkActor();
      if (!approved) {
        throw StateError(SkoLanguageController.isEnglish
            ? 'Approval was not saved. Check your seal surname, invoice calculation and approval permissions.'
            : '承認を保存できませんでした。承認印の名字・請求額の確定状態・承認権限を確認してください。');
      }
      final refreshed = _buildPreviewData().timeout(
        const Duration(seconds: 90),
        onTimeout: () => throw StateError(SkoLanguageController.tr('請求書の読み込みに時間がかかっています。通信を確認して再試行してください。')),
      );
      // Only report success after reading the server's actual saved approval.
      final data = await refreshed;
      checkActor();
      if (!data.approvals.any((item) => item.userId == row.userId && item.approved)) {
        throw StateError(SkoLanguageController.isEnglish
            ? 'Could not confirm the saved approval. Reload before trying again.'
            : '保存された承認を確認できませんでした。再操作の前に再読み込みしてください。');
      }
      if (!mounted) return;
      setState(() {
        _previewRevision++;
        _previewData = Future.value(data);
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
        SkoLanguageController.isEnglish ? 'Invoice approved' : '請求書を承認しました',
      )));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
        error is StateError ? error.message.toString()
            : (SkoLanguageController.isEnglish ? 'Could not confirm invoice approval. Check your surname, invoice calculation and approval permissions, then reload.' : '請求書の承認を確認できませんでした。名字・請求額の確定状態・承認権限を確認し、再読み込みしてください。'),
      )));
    } finally {
      if (mounted) setState(() => _approving = false);
    }
  }

  Future<void> _openAcceptanceEditor() async {
    if (_openingAcceptance || _singleInvoice?.invoiceId.isNotEmpty != true ||
        _singleInvoice?.documentUpdatedAt == null) {
      return;
    }
    setState(() => _openingAcceptance = true);
    try {
      await _readyForm();_actorLease.verify();
      final invoice = _singleInvoice!;
      final pending = _previewData;
      final data = await pending;
      if (!mounted) return;
      _formScope!.requireScope();_actorLease.verify();
      if (!identical(pending, _previewData)) return;
      final actor = SupabaseBackend.isInitialized
          ? SupabaseBackend.client.auth.currentUser?.id : null;
      final revision = DateTime.parse(invoice.documentUpdatedAt!).toUtc().toIso8601String();
      final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => TradeDocumentAttachmentEditorPage(
          subjectKind: 'invoice', subjectId: invoice.invoiceId,
          sourceRevision: revision,
          initialInput: actor == null ? null : R33Input(
            actorId: actor, companyId: invoice.companySealSnapshot.companyId ?? '',
            subjectId: invoice.invoiceId, sourceRevision: revision,
            text: data.settings?.invoiceSubject ?? '')),
      ));
      if (!mounted) return;
      _actorLease.verify();
      _formScope!.requireScope();
      if (saved == true) {
        setState(() {
          _previewRevision++;
          _previewData = _buildPreviewData();
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('請求書を再読み込みしてから注文請書を開いてください。')));
      }
    } finally {
      if (mounted) setState(() => _openingAcceptance = false);
    }
  }

  Widget _withoutPdf(Widget child) => FinancialPreviewChrome(
    actions: widget.additionalActions, status: const [],
    preview: child, footer: const SizedBox.shrink(),
  );

  @override
  Widget build(BuildContext context) {
    return TradeDocumentActorBoundary(child: Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? '請求書PDFプレビュー'),
      ),
      body: FutureBuilder<_InvoicePreviewData>(
        future: _previewData,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _withoutPdf(const Center(child: CircularProgressIndicator()));
          }
          if (snapshot.hasError || snapshot.data == null) {
            return _withoutPdf(InvoicePreviewFailure(
              title: '請求書プレビューを生成できませんでした',
              message: snapshot.error?.toString() ?? SkoLanguageController.tr('PDFデータが空です。'),
              onRetry: () => setState(() {
                _previewRevision++;
                _previewData = _buildPreviewData().timeout(
                  const Duration(seconds: 90),
                  onTimeout: () => throw StateError(SkoLanguageController.tr('請求書の読み込みに時間がかかっています。通信を確認して再試行してください。')),
                );
              }),
            ));
          }
          final previewData = snapshot.data!;
          final pdfBytes = previewData.pdfBytes;
          return Builder(
            builder: (context) {
              final approvals = previewData.approvals;
              final canApprove = approvals.any(
                (item) => item.canCurrentUserApprove,
              );
              final actorId = SupabaseBackend.isInitialized
                  ? SupabaseBackend.client.auth.currentUser?.id : null;
              final isPendingApprover = actorId != null && approvals.any(
                (item) => item.userId == actorId && item.status == 'pending',
              );
              final approvalEntry = InvoiceApprovalEntryActions(
                notificationOnly: invoiceNoticeApprovalReleased,
                canApprove: canApprove,
                isPendingApprover: isPendingApprover,
                fromNotification: widget.approvalFromNotification,
                busy: _approving,
                onLegacyApprove: invoiceNoticeApprovalReleased ? null : _approve,
                controller: null,
                recoveryController: _noticeController,
                notificationId: widget.approvalNotificationId ?? '',
                invoiceId: _singleInvoice?.invoiceId ?? '',
                revision: _singleInvoice?.documentUpdatedAt ?? '',
                confirmSavedApproval: () async {
                  final actor = SupabaseBackend.isInitialized
                      ? SupabaseBackend.client.auth.currentUser?.id : null;
                  if (actor == null) { return false; }
                  final data = await _buildPreviewData().timeout(const Duration(seconds: 90));
                  if (!mounted || !SupabaseBackend.isInitialized ||
                      SupabaseBackend.client.auth.currentUser?.id != actor) { return false; }
                  final saved = data.approvals.any((row) => row.userId == actor && row.approved);
                  if (saved) {
                    setState(() { _previewRevision++; _previewData = Future.value(data); });
                  }
                  return saved;
                },
              );
              return FinancialPreviewChrome(
                actions: [
                  ...widget.additionalActions,
                  if (previewData.missingAcceptanceCount == 0 &&
                      _singleInvoice?.invoiceId.isNotEmpty == true &&
                      _singleInvoice?.documentUpdatedAt != null)
                    TextButton.icon(
                      onPressed: _openingAcceptance ? null : _openAcceptanceEditor,
                      icon: const Icon(Icons.description_outlined, size: 20),
                      label: const Text('請書入力'),
                    ),
                  if (_singleInvoice?.invoiceId.isNotEmpty == true && _singleInvoice?.documentUpdatedAt != null)
                    TextButton.icon(onPressed: _openingAcceptance ? null : _formOutput,
                      icon: const Icon(Icons.print_outlined, size: 20), label: const Text('請書保存・印刷')),
                  if (_singleInvoice != null)
                    TradeConfirmationAction(kind: 'invoice', parentId: _singleInvoice!.invoiceId,
                      sourceRevision: '', label: '承認済み請書', inspectOnly: true),
                  IconButton(tooltip: '表示・保存の案内',
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    onPressed: () => showModalBottomSheet<void>(context: context, isScrollControlled: true,
                      builder: (context) => SafeArea(child: SingleChildScrollView(
                        child: InvoicePreviewGuidance(initiallyExpanded: true,
                          needsStampSurname: approvals.any((row) => row.stampSurname == null))))),
                    icon: Icon(approvals.any((row) => row.stampSurname == null)
                        ? Icons.info_outline : Icons.help_outline, size: 22)),
                ],
                status: [
                  if (previewData.missingAcceptanceCount > 0)
                    InvoiceAcceptanceNotice(
                      missingCount: previewData.missingAcceptanceCount,
                      singleInvoice: _singleInvoice != null,
                      onReview: !_openingAcceptance &&
                          _singleInvoice?.invoiceId.isNotEmpty == true &&
                          _singleInvoice?.documentUpdatedAt != null
                          ? _openAcceptanceEditor : null,
                    ),
                  if (approvals.isNotEmpty)
                    InvoicePreviewApprovalStatus(
                      approvals: approvals,
                      surnameAction: approvals.any((row) => row.canCurrentUserSetStampSurname)
                          ? TextButton.icon(onPressed: _approving ? null : _setApprovalSurname,
                              icon: const Icon(Icons.badge_outlined),
                              label: Text(SkoLanguageController.isEnglish ? 'Seal surname' : '名字設定'))
                          : null,
                      approvalAction: invoiceNoticeApprovalReleased ? null : approvalEntry,
                    ),
                  if (invoiceNoticeApprovalReleased)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                      child: approvalEntry,
                    ),

                ],
                preview: Container(
                      key: ValueKey(_previewRevision),
                      color: Colors.grey.shade200,
                      alignment: Alignment.topCenter,
                      child: _InvoicePdfZoomView(
                        key: ValueKey('invoice_pdf_preview_$_previewRevision'),
                        pdfBytes: pdfBytes,
                      ),
                    ),
                footer: Row(children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48), textStyle: const TextStyle(fontSize: 14)),
                              onPressed: () async { _actorLease.verify(); await Printing.layoutPdf(
                                name: InvoicePdfService.fileNameFor(
                                  widget.invoices,
                                  title: widget.title,
                                ),
                                format: PdfPageFormat.a4,
                                onLayout: (_) async { _actorLease.verify(); return pdfBytes; },
                              ); },
                              icon: const Icon(Icons.print_outlined),
                              label: const Text('印刷'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(minimumSize: const Size(0, 48), textStyle: const TextStyle(fontSize: 14)),
                              onPressed: () async { _actorLease.verify(); await Printing.sharePdf(
                                bytes: pdfBytes,
                                filename: InvoicePdfService.fileNameFor(
                                  widget.invoices,
                                  title: widget.title,
                                ),
                              ); },
                              icon: const Icon(Icons.ios_share_outlined),
                              label: Text(SkoLanguageController.tr('保存・共有')),
                            ),
                          ),
                          ]),
              );
            },
          );
        },
      ),
    ));
  }
}

/// Approval text and actions wrap independently at narrow widths and large text.
class InvoicePreviewApprovalStatus extends StatelessWidget {
  const InvoicePreviewApprovalStatus({super.key, required this.approvals,
    this.surnameAction, this.approvalAction});
  final List<InvoiceApprovalRecord> approvals;
  final Widget? surnameAction, approvalAction;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(approvals.map((item) => '${item.name}：${item.approved ? '承認済み' : '承認待ち'}').join('　'),
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        if (surnameAction != null) surnameAction!,
        if (approvalAction != null) approvalAction!,
      ]),
    ]),
  );
}

/// Optional preview instructions stay collapsed so the document has priority.
class InvoicePreviewGuidance extends StatelessWidget {
  const InvoicePreviewGuidance({super.key, this.needsStampSurname = false, this.initiallyExpanded = false});
  final bool needsStampSurname;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    final english = SkoLanguageController.isEnglish;
    return ExpansionTile(
      initiallyExpanded: initiallyExpanded,
      dense: true,
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      title: Text(english ? 'Display and save help' : '表示・保存の案内'),
      leading: Icon(needsStampSurname ? Icons.info_outline : Icons.help_outline),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 160),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (needsStampSurname) ...[
                  Text(english
                      ? 'Approval-seal surname unconfigured or unconfirmed: existing seals are retained. Set your surname before a new approval when available.'
                      : '承認印の名字未設定・未確認：既存の印影を保持しています。設定が利用可能な場合は、新しい承認前に本人の名字を入力してください。'),
                  const SizedBox(height: 8),
                ],
                Text(english
                    ? 'The A4 page fits the screen width. Pinch the preview to zoom in or out.'
                    : 'A4を画面幅に合わせて表示します。プレビュー上で拡大・縮小できます。'),
                const SizedBox(height: 8),
                Text(SkoLanguageController.tr('iPhoneでは共有メニューの「ファイルに保存」でPDFを保存できます。')),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Displays raster pages from the exact PDF used for printing and sharing.
/// The viewport stays bounded before applying scale, including on iPhone.
class _InvoicePdfZoomView extends StatefulWidget {
  const _InvoicePdfZoomView({super.key, required this.pdfBytes});
  final Uint8List pdfBytes;
  @override
  State<_InvoicePdfZoomView> createState() => _InvoicePdfZoomViewState();
}

class _InvoicePdfZoomViewState extends State<_InvoicePdfZoomView> {
  bool get _nativeInvoicePreview => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  final TransformationController _pdfZoom = TransformationController();
  late Future<List<Uint8List>> _pages;
  bool _isZoomed = false;
  double _scale = 1;
  Size _viewport = Size.zero;

  @override
  void initState() {
    super.initState();
    if (!_nativeInvoicePreview) _pages = _rasterPages();
    _pdfZoom.addListener(_readScale);
  }

  @override
  void didUpdateWidget(covariant _InvoicePdfZoomView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.pdfBytes, widget.pdfBytes)) {
      if (!_nativeInvoicePreview) _pages = _rasterPages();
      _pdfZoom.value = Matrix4.identity();
    }
  }

  Future<List<Uint8List>> _rasterPages() => collectInvoicePreviewPages(
    Printing.raster(widget.pdfBytes, dpi: 120).asyncMap((page) => encodeInvoicePreviewRaster(
      width: page.width, height: page.height, pixels: page.pixels,
      encode: page.toPng,
    )),
  );

  void _retryRaster() {
    setState(() => _pages = _rasterPages());
  }

  void _readScale() {
    final scale = _pdfZoom.value.getMaxScaleOnAxis();
    if (mounted && (scale - _scale).abs() > .005) {
      setState(() {
        _scale = scale;
        _isZoomed = scale > 1.01;
      });
    }
  }

  void _setScale(double scale) {
    final bounded = scale.clamp(1.0, 5.0).toDouble();
    _pdfZoom.value = Matrix4.identity()
      ..translateByDouble(
        -_viewport.width * (bounded - 1) / 2,
        -_viewport.height * (bounded - 1) / 2,
        0,
        1,
      )
      ..scaleByDouble(bounded, bounded, 1, 1);
  }

  @override
  void dispose() {
    _pdfZoom.removeListener(_readScale);
    _pdfZoom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _nativeInvoicePreview
      ? InvoiceNativePdfView(pdfBytes: widget.pdfBytes)
      : Column(
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: '縮小',
            onPressed: _scale > 1.01 ? () => _setScale(_scale / 1.4) : null,
            icon: const Icon(Icons.zoom_out),
          ),
          TextButton(
            onPressed: () => _setScale(1),
            child: Text('${(_scale * 100).round()}%'),
          ),
          IconButton(
            tooltip: '拡大',
            onPressed: _scale < 4.99 ? () => _setScale(_scale * 1.4) : null,
            icon: const Icon(Icons.zoom_in),
          ),
        ],
      ),
      Expanded(
        child: LayoutBuilder(
          builder: (context, constraints) {
            _viewport = Size(constraints.maxWidth, constraints.maxHeight);
            return FutureBuilder<List<Uint8List>>(
              future: _pages,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return InvoicePreviewFailure(
                    title: 'PDFを表示できませんでした',
                    message: snapshot.error.toString(),
                    onRetry: _retryRaster,
                    pdfReady: true,
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return InteractiveViewer(
                  transformationController: _pdfZoom,
                  minScale: 1,
                  maxScale: 5,
                  child: SizedBox(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    child: SingleChildScrollView(
                      physics: _isZoomed
                          ? const NeverScrollableScrollPhysics()
                          : const ClampingScrollPhysics(),
                      child: Column(
                        children: [
                          for (final page in snapshot.data!)
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Image.memory(
                                page,
                                width: constraints.maxWidth - 24,
                                fit: BoxFit.fitWidth,
                                gaplessPlayback: true,
                                filterQuality: FilterQuality.high,
                                errorBuilder: (context, error, stack) => InvoicePreviewFailure(
                                  title: 'PDFを表示できませんでした',
                                  message: SkoLanguageController.tr('PDFのページ画像を表示できませんでした。'),
                                  onRetry: _retryRaster,
                                  pdfReady: true,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    ],
  );
}

class _InvoicePreviewData {
  const _InvoicePreviewData({
    required this.pdfBytes,
    required this.settings,
    required this.approvals,
    this.missingAcceptanceCount = 0,
  });
  final int missingAcceptanceCount;
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
    final rows = InvoicePdfService._detailRows(invoice);
    final totals = DocumentDisplayTotals.invoice(invoice);
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
                        _summary('小計', totals.workSubtotal),
                        _summary('福利厚生費', totals.welfare),
                        _summary('消費税', invoice.taxYen),
                        _summary('請求金額（税込）', invoice.grandTotalYen, strong: true),
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
