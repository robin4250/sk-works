import '../shared/trade_document_actor_boundary.dart';
import '../shared/document_display_totals.dart';
import '../shared/trade_document_attachment.dart';
import '../shared/trade_document_attachment_repository.dart';
import 'payment_order_pdf.dart';
import 'payment_order_resolver.dart';
import '../expenses/expense_document_repository.dart';
import '../expenses/expense_detail_pdf.dart';
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
    ExpenseDocumentDetails? expenseDetails,
    TradeDocumentAttachment? orderAttachment,
    PdfPageFormat format = PdfPageFormat.a4,
    pw.Font? regularFont,
    pw.Font? boldFont,
  }) async {
    final actorLease=TradeDocumentActorLease();
    try {
    record.verifyDirectionalExpense();
    final expenses = expenseDetails ?? (record.isAgreementSnapshot || record.isPreview ? null : await ExpenseDocumentRepository.load(ExpenseDocument.paymentCertificate, record.id, record.periodStart, revision:record.revision));
    if (record.hasDirectionalExpense) {
      if (expenses?.directionalCost == null || expenses!.kind != ExpenseDocument.paymentCertificate ||
          expenses.documentId != record.id || expenses.subjectId != record.partnerCompanyId ||
          expenses.claims.companyId != record.directionalExpenseRead!.directionalCost!.context.companyId) {
        throw StateError('方向付き経費の同版明細を確認できません。');
      }
      record.directionalExpenseRead!.directionalCost!.verifyDetails({...expenses.directionalCost!.fields, 'claims': expenses.claims.entries.map((claim) => {
        'id': claim.id, 'revision': claim.revision, 'amount_yen': claim.amountYen,
      }).toList()});
    }
    if (!record.hasDirectionalExpense && expenses?.directionalCost != null) throw StateError('経費の方向版が変更されました。再読み込みしてください。');
    if ((record.expenseCost.isCurrent || record.hasDirectionalExpense) && expenses?.costRecoveryAmountYen != record.expenseExtraAmountYen) {
      throw StateError('別途経費の内訳と支払証明書金額が一致しません。再読み込みしてください。');
    }
    if (expenses != null) {
      record.expenseCost.verifyDetails(expenses.claims.entries.map((claim) => {
        'id': claim.id, 'revision': claim.revision, 'amount_yen': claim.amountYen,
      }));
    }
    final regular = regularFont ?? await PdfGoogleFonts.notoSansJPRegular();
    final bold = boldFont ?? await PdfGoogleFonts.notoSansJPBold();
    final sealFont = record.payerCompanySealEnabled
        ? await CompanySealPdf.loadStyleFont(record.companySealSnapshot.style)
        : regular;
    final document = pw.Document(
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(
          12 * PdfPageFormat.mm,
          10 * PdfPageFormat.mm,
          12 * PdfPageFormat.mm,
          10 * PdfPageFormat.mm,
        ),
        header: (context) => _pageHeader(record, context),
        footer: (_) => _pageFooter(record),
        build: (_) => _sheet(record, sealFont, regular),
      ),
    );

    final savedOrder = orderAttachment ?? (record.isPreview || record.isAgreementSnapshot ||
        !RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(record.id) ? null :
        await _resolveOrder(record));
    if(savedOrder!=null){
      if(savedOrder.payload['month']!='${record.periodStart.year}-${record.periodStart.month.toString().padLeft(2,'0')}') {
        throw StateError('注文書の対象月が一致しません。');
      }
      await PaymentOrderPdf.append(document,savedOrder,regularFont:regular,boldFont:bold);
    }
    if (expenses != null) {
      ExpenseDetailPdf.append(document, claims:expenses.claims, kind:ExpenseDocument.paymentCertificate, subjectId:expenses.subjectId, regularFont:regular, boldFont:bold, costRecoveryAmountYen:expenses.costRecoveryAmountYen, costRecoveryIsDeduction:record.hasDirectionalExpense);
    }
    final bytes=await document.save();
    actorLease.verify();
    return bytes;
    }finally{actorLease.dispose();}
  }

  static Future<TradeDocumentAttachment?> _resolveOrder(PaymentCertificateRecord record) async {
    final repository = TradeDocumentAttachmentRepository.maybeCreate();
    if (repository == null) return null;
    return PaymentOrderResolver.resolve(await repository.loadWorkspace(
      subjectKind: 'payment_certificate', subjectId: record.id,
      sourceRevision: record.revision.toString(),
    ));
  }

  static Future<bool> printCertificate(PaymentCertificateRecord record) {
    return Printing.layoutPdf(
      name: '${record.monthLabel}_${record.partnerCompanyName}_支払証明書.pdf',
      format: PdfPageFormat.a4,
      onLayout: (_) => buildPdf(record),
    );
  }

  static List<pw.Widget> _sheet(
    PaymentCertificateRecord record,
    pw.Font sealFont,
    pw.Font fallbackFont,
  ) {
    final welfare = record.lines.where((line) => isDocumentWelfareLabel(line.workContent))
        .fold<int>(0, (sum, line) => sum + line.amountYen);
    final tax = record.lines.where((line) => isDocumentTaxLabel(line.workContent))
        .fold<int>(0, (sum, line) => sum + line.amountYen);
    final finalItems = record.documentAdjustments.where((item) => item.isFinalAmount).toList();
    final finalPlus = finalItems.where((item) => item.sign == 'plus').fold<int>(0, (sum, item) => sum + item.amountYen);
    final finalMinus = finalItems.where((item) => item.sign == 'minus').fold<int>(0, (sum, item) => sum + item.amountYen);
    final display = DocumentDisplayTotals(workSubtotal: record.grossAmount - finalPlus - welfare - tax + (record.hasDirectionalExpense ? record.expenseLineDeltaYen : 0),
      welfare: welfare, tax: tax, total: record.netAmount);
    final baseAmount = display.workSubtotal - record.expenseLineDeltaYen;
    final lines = [
      if (record.lines.isEmpty && (!(record.expenseCost.isCurrent || record.hasDirectionalExpense) || baseAmount != 0))
            PaymentCertificateLine(
              siteName: '工事代金',
              workContent: '',
              quantityLabel: '1',
              unitPriceYen: baseAmount,
              amountYen: baseAmount,
            ),
      ...record.lines.where((line) => !isDocumentWelfareLabel(line.workContent) && !isDocumentTaxLabel(line.workContent)),
      if (record.expenseExtraAmountYen != 0)
        PaymentCertificateLine(
          siteName: '経費', workContent: record.hasDirectionalExpense ? '経費差引（原額）' : '別途経費（原額）', quantityLabel: '一式',
          unitPriceYen: record.expenseLineDeltaYen,
          amountYen: record.expenseLineDeltaYen,
        ),
    ];

    return [
        pw.SizedBox(height: 22),
        pw.Center(child: pw.Text(
          '工事代金支払明細書',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: 19,
            fontWeight: pw.FontWeight.bold,
            decoration: pw.TextDecoration.underline,
          ),
        )),
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
              child: pw.ConstrainedBox(
                constraints: pw.BoxConstraints(
                  // Retain the issuer block footprint above the detail table.
                  minHeight: 55 + 10 * [
                    record.payerPostalCode,
                    record.payerAddress,
                    record.payerPhone,
                    record.payerFax,
                  ].where((value) => value.isNotEmpty).length.toDouble(),
                ),
                child: pw.Stack(
                  children: [
                    pw.Padding(
                      // One shared edge, outside the unchanged 55pt seal lane.
                      padding: const pw.EdgeInsets.only(top: 21, right: 60),
                      child: pw.SizedBox(
                        width: 150,
                        child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text(
                            record.companySealSnapshot.registeredName(
                                record.payerCompanyName),
                            textAlign: pw.TextAlign.right,
                            style: pw.TextStyle(
                              fontSize: 9,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          if (record.payerPostalCode.isNotEmpty)
                            _issuerDetail('〒${formatPostalCode(record.payerPostalCode)}'),
                          if (record.payerAddress.isNotEmpty)
                            _issuerDetail(record.payerAddress),
                          if (record.payerPhone.isNotEmpty)
                            _issuerDetail('TEL　${formatPhone(record.payerPhone)}'),
                          if (record.payerFax.isNotEmpty)
                            _issuerDetail('FAX　${formatPhone(record.payerFax)}'),
                        ],
                        ),
                      ),
                    ),
                    if (record.payerCompanySealEnabled)
                      pw.Positioned(
                        right: 0,
                        top: 0,
                        child: CompanySealPdf.build(
                          record.companySealSnapshot.registeredName(
                              record.payerCompanyName),
                          style: record.companySealSnapshot.style,
                          companyId: record.companySealSnapshot.companyId, uploadedPng: record.companySealSnapshot.uploadedPng,
                          size: 55,
                          font: sealFont,
                          fallbackFont: fallbackFont,
                        ),
                      ),
                  ],
                ),
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
              repeat: true,
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
            for (final item in [
              ('小計', display.workSubtotal), ('福利厚生費', display.welfare), ('消費税', display.tax),
            ]) pw.TableRow(
              children: [
                _cell(''),
                _cell(item.$1, right: true),
                _cell(''),
                _cell(''),
                _cell(_number(item.$2), right: true),
              ],
            ),
            for (final item in finalItems) pw.TableRow(children: [
              _cell('調整'), _cell('${item.title}（追加税なし）'), _cell(''), _cell(''),
              _cell(_number(item.signedYen), right: true),
            ]),
            pw.TableRow(
              children: [
                _cell(''),
                _cell('支払金額', right: true, bold: true),
                _cell(''),
                _cell(''),
                _cell(
                  display.total == 0 ? '' : '¥${_number(display.total)}',
                  right: true,
                  bold: true,
                  fontSize: 10,
                ),
              ],
            ),
          ],
        ),
        if (record.deductions - finalMinus != 0) pw.Padding(
          padding: const pw.EdgeInsets.only(top: 5),
          child: pw.Text('控除 ${_number(-(record.deductions - finalMinus))}円（支払金額に反映済み）', style: const pw.TextStyle(fontSize: 8))),
        if (record.lines.isEmpty && record.grossAmount != 0) pw.Text(
          '※福利厚生費・消費税の内訳は保存されていません。保存済みの支払金額を表示しています。',
          style: const pw.TextStyle(fontSize: 7)),
    ];
  }

  static pw.Widget _pageHeader(PaymentCertificateRecord record, pw.Context context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(child: pw.Text(
              'From:${record.companySealSnapshot.registeredName(record.payerCompanyName)}',
              style: const pw.TextStyle(fontSize: 7),
            )),
            pw.SizedBox(width: 8),
            pw.Text(record.payerPhone, style: const pw.TextStyle(fontSize: 7)),
            pw.SizedBox(width: 12),
            pw.Text('P.${context.pageNumber.toString().padLeft(3, '0')}/${context.pagesCount.toString().padLeft(3, '0')}', style: const pw.TextStyle(fontSize: 7)),
          ],
        );

  static pw.Widget _pageFooter(PaymentCertificateRecord record) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              '対象期間：${_date(record.periodStart)} ～ ${_date(record.periodEnd)}',
              style: const pw.TextStyle(fontSize: 7),
            ),
            pw.Text(
              record.isAgreementSnapshot
                  ? '双方確認済み・第${record.revision}版'
                  : record.isPreview
                  ? 'プレビュー・出勤実績なし'
                  : record.status == 'draft'
                  ? '下書き・第${record.revision}版'
                  : '確定・第${record.revision}版',
              style: const pw.TextStyle(fontSize: 7),
            ),
          ],
        );

  static pw.Widget _issuerDetail(String value) => pw.Text(
    value,
    textAlign: pw.TextAlign.right,
    style: const pw.TextStyle(fontSize: 8),
  );

  static String formatPostalCode(String value) {
    final trimmed = value.trim();
    return RegExp(r'^\d{7}$').hasMatch(trimmed)
        ? '${trimmed.substring(0, 3)}-${trimmed.substring(3)}'
        : value;
  }

  static String formatPhone(String value) {
    final trimmed = value.trim();
    return RegExp(r'^(03|06)\d{8}$').hasMatch(trimmed)
        ? '${trimmed.substring(0, 2)}-${trimmed.substring(2, 6)}-${trimmed.substring(6)}'
        : value;
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
    if (RegExp(r'^[+-]?0+(?:\.0+)?\s*(?:日|時間|回|人|人工)?$').hasMatch(trimmed)) {
      return '';
    }
    return value;
  }
}
