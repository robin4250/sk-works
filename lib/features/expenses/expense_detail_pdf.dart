import 'dart:math' as math;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'expense_claim.dart';

enum ExpenseDocument { payroll, invoice, paymentCertificate }

/// Appends details to a caller-owned document, normally immediately after its
/// first page. It never rewrites the first page or calculates a payable amount.
class ExpenseDetailPdf {
  const ExpenseDetailPdf._();
  static void append(
    pw.Document document, {
    required ExpenseClaims claims,
    required ExpenseDocument kind,
    required String subjectId,
    required pw.Font regularFont,
    required pw.Font boldFont,
  }) {
    final selected = switch (kind) {
      ExpenseDocument.payroll => claims.forApplicant(subjectId),
      ExpenseDocument.invoice => claims.forCounterparty(
        ExpenseCategory.customer,
        subjectId,
      ),
      ExpenseDocument.paymentCertificate => claims.forCounterparty(
        ExpenseCategory.subcontractor,
        subjectId,
      ),
    };
    if (selected.entries.isEmpty) return;
    final rows = <pw.TableRow>[];
    pw.Widget cell(String text, {bool header = false}) => pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        text,
        style: pw.TextStyle(font: header ? boldFont : regularFont, fontSize: 9),
      ),
    );
    rows.add(
      pw.TableRow(
        repeat: true,
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          for (final title in ['日付・申請ID', '申請者・内容', '承認・振り分け', '申請額'])
            cell(title, header: true),
        ],
      ),
    );
    for (final claim in selected.entries) {
      final columns = [
        _chunks(
          '${claim.incurredOn.year}/${claim.incurredOn.month}/${claim.incurredOn.day}\n${claim.id}',
          28,
        ),
        _chunks('${claim.applicantName}\n${claim.description}', 90),
        _chunks(
          '${expenseClaimStatusLabel(claim)}\n${expenseCategoryLabel(claim.allocation.category)}'
          '${claim.allocation.counterpartyName == null ? '' : '\n${claim.allocation.counterpartyName}'}',
          32,
        ),
        ['${claim.amountYen}円'],
      ];
      final count = columns.map((parts) => parts.length).reduce(math.max);
      for (var i = 0; i < count; i++) {
        rows.add(
          pw.TableRow(
            children: [
              for (final parts in columns)
                cell(i < parts.length ? parts[i] : ''),
            ],
          ),
        );
      }
    }
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        maxPages: 1000,
        theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
        header: (_) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 12),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                '経費申請明細',
                style: pw.TextStyle(font: boldFont, fontSize: 17),
              ),
              pw.Text(
                '承認・未承認・却下の履歴を表示。却下は精算対象外です。',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.Text(
                '申請額の一覧です。支給・請求・支払額は表紙をご確認ください。',
                style: const pw.TextStyle(fontSize: 9),
              ),
            ],
          ),
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            '${context.pageNumber}',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ),
        build: (_) => selected.entries.isEmpty
            ? [pw.Text('対象の申請はありません。')]
            : [
                pw.Table(
                  columnWidths: const {
                    0: pw.FlexColumnWidth(1.3),
                    1: pw.FlexColumnWidth(3.1),
                    2: pw.FlexColumnWidth(1.8),
                    3: pw.FlexColumnWidth(1.1),
                  },
                  border: pw.TableBorder.all(
                    color: PdfColors.grey400,
                    width: 0.4,
                  ),
                  children: rows,
                ),
              ],
      ),
    );
  }

  static List<String> _chunks(String text, int size) {
    final parts = <String>[];
    final current = <int>[];
    var lines = 1;
    for (final rune in text.runes) {
      current.add(rune);
      if (rune == 10) lines++;
      if (current.length >= size || lines >= 4) {
        parts.add(String.fromCharCodes(current));
        current.clear();
        lines = 1;
      }
    }
    if (current.isNotEmpty) parts.add(String.fromCharCodes(current));
    return parts;
  }
}
