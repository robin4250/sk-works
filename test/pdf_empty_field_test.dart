import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/features/shared/company_seal_pdf.dart';
import 'package:sk_works/features/shared/standalone_trade_document.dart';
import 'package:sk_works/features/shared/trade_document_form_renderer.dart';
import 'package:sk_works/domain/trade_document_form_draft.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<void> renderSeal(String name) async {
    final font = await CompanySealPdf.loadFont();
    final pdf = pw.Document(theme: pw.ThemeData.withFont(base: font, bold: font));
    pdf.addPage(pw.Page(build: (_) => CompanySealPdf.build(name, font: font)));
    final bytes = await pdf.save();
    expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
  }
  test('empty and whitespace-only registered names remain empty widgets', () async {
    for (final name in ['', ' ', '\t', '\u3000', ' \u3000 ']) {
      expect(CompanySealPdf.verticalColumns(name), isEmpty);
      await renderSeal(name);
    }
  });
  test('interior ASCII and ideographic space cells preserve names without zero-width fit', () async {
    for (final name in ['Synthetic issuer', '合成 自社', '合成\u3000自社', '合成\t自社']) {
      expect(CompanySealPdf.verticalColumns(name).join(), name);
      await renderSeal(name);
    }
  });
  test('normal and long registered names still render', () async {
    for (final name in ['合成自社株式会社', '合成会社', 'SyntheticCompany', '合成とても長い会社名 空白を含む名称株式会社']) {
      await renderSeal(name);
    }
  });
  test('valid-date acceptance no amounts and blank optional fields renders real PDF with space-containing seal', () async {
    final attachment = standaloneTradeDocument(context: {
      'acceptance': true,
      'issuer': {'name': 'Synthetic issuer', 'address': 'Synthetic address', 'representative_name': 'Synthetic representative'},
      'counterparty': {'name': 'Synthetic recipient', 'address': 'Synthetic recipient address', 'representative_name': 'Synthetic recipient representative'},
      'company_seal_enabled': true,
      'company_seal_snapshot': {'version': 1, 'style': 'legacy', 'name': 'Synthetic issuer'},
    }, fields: {
      'work_name': 'Synthetic work', 'work_address': 'Synthetic place',
      'issue_date': '2026-10-21', 'order_date': '2026-10-20',
      'acceptance_text': '{order_date}付の注文を承諾します。',
    });
    final draft = TradeDocumentFormDraft.fromPayload(attachment.payload,
      allowAmountEditing: true, initializeExtendedFields: true, initializeDefaults: true);
    draft.validateForSave();
    final before = jsonEncode(draft.payload);
    final bytes = await TradeDocumentFormRenderer.canonical(draft.payload);
    expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
    expect(bytes.length, greaterThan(100));
    expect(jsonEncode(draft.payload), before);
    expect(draft.payload.containsKey('total_amount_yen'), isFalse);
    expect(draft.payload.containsKey('tax_amount_yen'), isFalse);
    expect((draft.payload['issuer'] as Map)['name'], 'Synthetic issuer');
  });
}
