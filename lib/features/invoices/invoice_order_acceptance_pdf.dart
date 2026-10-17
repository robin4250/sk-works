import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../domain/company_seal_snapshot.dart';
import '../shared/company_seal_pdf.dart';
import '../shared/trade_document_attachment.dart';

/// The acceptance is rendered from its saved party/date/seal snapshot only.
/// Invoice amounts and the adopted first-page template remain independent.
class InvoiceOrderAcceptancePdf {
  const InvoiceOrderAcceptancePdf._();

  static Future<void> append(
    pw.Document document,
    TradeDocumentAttachment attachment, {
    required pw.Font regularFont,
    required pw.Font boldFont,
  }) async {
    final payload = attachment.payload;
    if (payload['kind'] != 'acceptance') {
      throw StateError('請求書の添付書類が注文請書ではありません。');
    }
    final issuer = Map<String, dynamic>.from(payload['issuer'] as Map);
    final customer = Map<String, dynamic>.from(payload['counterparty'] as Map);
    final orderDate = _date(payload['order_date']);
    final issueDate = _date(payload['issue_date']);
    final acceptanceText = payload['acceptance_text']?.toString().trim().isNotEmpty == true
        ? payload['acceptance_text'].toString()
        : '乙は、貴殿から受領した$orderDate付の注文書記載の条件通り、本工事を請け負うことを承諾いたします。';
    final workName = payload['work_name']?.toString().trim() ?? '';
    final notes = payload['notes']?.toString().trim() ?? '';
    final compact = workName.length > 80 || notes.isNotEmpty || acceptanceText.length > 180 || issuer['address'].toString().length > 120 ||
        issuer['name'].toString().length > 60 || customer['name'].toString().length > 60;
    final gap = compact ? 8.0 : 40.0;
    final seal = CompanySealSnapshot.fromJson(payload['company_seal_snapshot']);
    final sealEnabled = payload['company_seal_enabled'] == true;
    final font = sealEnabled
        ? await CompanySealPdf.loadStyleFont(seal.style)
        : regularFont;
    document.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 48, vertical: 48),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Center(child: pw.Text('注文請書', style: pw.TextStyle(
            font: boldFont, fontSize: 23, letterSpacing: 5))),
          pw.SizedBox(height: 12),
          pw.Center(child: pw.Text('${payload['month']} 月分', style: const pw.TextStyle(fontSize: 11))),
          pw.SizedBox(height: 28),
          pw.Text('（甲・発注者）', style: const pw.TextStyle(fontSize: 11)),
          pw.SizedBox(height: 10),
          pw.Text('${customer['name']}　御中', style: pw.TextStyle(
            font: boldFont, fontSize: compact ? 9 : 16)),
          pw.SizedBox(height: gap),
          if (workName.isNotEmpty) ...[
            _field('工事名', workName, compact: compact),
            pw.SizedBox(height: 8),
          ],
          pw.Text(
            acceptanceText,
            style: pw.TextStyle(fontSize: compact ? 8 : 13, lineSpacing: compact ? 1 : 9),
          ),
          if (notes.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Text('特記事項', style: pw.TextStyle(font: boldFont, fontSize: 9)),
            pw.Text(notes, style: const pw.TextStyle(fontSize: 8, lineSpacing: 1)),
          ],
          pw.SizedBox(height: gap),
          pw.Align(alignment: pw.Alignment.centerRight,
            child: pw.Text(issueDate, style: const pw.TextStyle(fontSize: 11))),
          pw.SizedBox(height: gap),
          pw.Text('（乙・受注者）', style: pw.TextStyle(font: boldFont, fontSize: 12)),
          pw.SizedBox(height: 12),
          _field('社名', issuer['name'], compact: compact),
          _field('住所', issuer['address'], compact: compact),
          _field('法人番号', issuer['corporate_number'], compact: compact),
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(child: _field('代表者名', issuer['representative_name'], compact: compact)),
            if (sealEnabled) pw.SizedBox(width: 16),
            if (sealEnabled) pw.SizedBox(width:64,height:64,child:CompanySealPdf.build(
              seal.registeredName(issuer['name'].toString()),
              size: 64, font: font, fallbackFont: regularFont,
              style: seal.style, companyId: seal.companyId)),
          ]),
        ],
      ),
    ));
  }

  static pw.Widget _field(String label, Object? value, {bool compact = false}) => pw.Padding(
    padding: pw.EdgeInsets.only(bottom: compact ? 6 : 15),
    child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.SizedBox(width: 75, child: pw.Text('$label：', style: pw.TextStyle(fontSize: compact ? 8 : 11))),
      pw.Expanded(child: pw.Text(value?.toString() ?? '', style: pw.TextStyle(fontSize: compact ? 8 : 11))),
    ]),
  );

  static String _date(Object? raw) {
    final text = raw?.toString() ?? '';
    final parsed = DateTime.tryParse(text);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text) || parsed == null ||
        parsed.toIso8601String().substring(0, 10) != text) {
      throw StateError('注文請書の日付を確認してください。');
    }
    return '${parsed.year}年${parsed.month}月${parsed.day}日';
  }
}

