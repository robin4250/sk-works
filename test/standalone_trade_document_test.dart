import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/features/shared/standalone_trade_document.dart';
import 'package:sk_works/features/shared/company_seal_pdf.dart';
import 'package:sk_works/features/payroll/payment_order_pdf.dart';
import 'package:sk_works/features/invoices/invoice_order_acceptance_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Map<String, dynamic> context(bool acceptance) => {
    'acceptance': acceptance,
    'issuer': {'name': '株式会社自社', 'address': '東京都1', 'representative_name': '自社代表', 'corporate_number': '1234567890123'},
    'counterparty': {'name': '株式会社登録相手', 'address': '大阪府1', 'representative_name': '相手代表', 'corporate_number': '9876543210987'},
    'company_seal_enabled': true,
    'company_seal_snapshot': {'version': 1, 'style': 'legacy', 'name': '株式会社自社'},
  };
  Map<String, String> fields() => {
    'work_name': '登録した工事初期文', 'work_address': '登録した工事場所',
    'issue_date': '2026-10-21', 'order_date': '2026-10-20',
    'period_start': '2026-10-01', 'period_end': '2026-10-31',
    'total_amount_yen': '110000', 'tax_amount_yen': '10000',
    'intro_text': '正式な発注内容', 'acceptance_text': '{order_date}付の注文を承諾します。',
    'payment_conditions': '合意した支払条件', 'notes': '合意した特記事項',
  };
  test('order requires entered amounts and never substitutes assumed zero', () {
    final f = fields()..remove('total_amount_yen');
    expect(() => standaloneTradeDocument(context: context(false), fields: f), throwsStateError);
    f['total_amount_yen'] = '110000';
    expect(standaloneTradeDocument(context: context(false), fields: f).payload['total_amount_yen'], 110000);
  });
  test('acceptance does not invent a financial amount or replace registered parties', () {
    final c = context(true);
    final original = Map<String, dynamic>.from(c['issuer'] as Map);
    final f = fields()..remove('total_amount_yen')..remove('tax_amount_yen')..['issuer.name'] = '偽の会社';
    final result = standaloneTradeDocument(context: c, fields: f);
    expect(result.payload.containsKey('total_amount_yen'), false);
    expect(result.payload['work_address'], '登録した工事場所');
    expect(result.payload['issuer'], original);
    expect(c['issuer'], original);
  });
  test('missing construction and invalid dates, money or party contracts fail', () {
    for (final entry in <String, String>{'work_name': '', 'work_address': '',
      'issue_date': '2026-02-30', 'period_end': '2026-09-30',
      'tax_amount_yen': '110001', 'issuer.representative_name': '代' * 81,
      'counterparty.corporate_number': '１２３４５６７８９０１２３'}.entries) {
      expect(() => standaloneTradeDocument(context: context(false), fields: fields()..[entry.key] = entry.value), throwsStateError);
    }
  });
  test('both registration generators produce a front and complete terms page', () async {
    final font = await CompanySealPdf.loadFont();
    for (final acceptance in [false, true]) {
      final result = standaloneTradeDocument(context: context(acceptance), fields: fields());
      final doc = pw.Document(theme: pw.ThemeData.withFont(base: font, bold: font));
      if (acceptance) {
        await InvoiceOrderAcceptancePdf.append(doc, result, regularFont: font, boldFont: font);
      } else {
        await PaymentOrderPdf.append(doc, result, regularFont: font, boldFont: font);
      }
      final bytes = await doc.save();
      expect(bytes.length, greaterThan(1000));
      expect(RegExp(r'/Type\s*/Page\b').allMatches(String.fromCharCodes(bytes)), hasLength(2));
      final output = Platform.environment['SKO_PDF_OUTPUT_DIR'];
      if (output != null) {
        Directory(output).createSync(recursive: true);
        File('$output/standalone-${acceptance ? 'acceptance' : 'order'}.pdf').writeAsBytesSync(bytes);
      }
    }
  });
}
