import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/features/shared/company_seal_pdf.dart';
import 'package:sk_works/features/shared/trade_document_attachment.dart';
import 'package:sk_works/features/shared/trade_document_company_name_pdf.dart';
import 'package:sk_works/features/payroll/payment_order_pdf.dart';
import 'package:sk_works/features/invoices/invoice_order_acceptance_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('generated seal columns omit only line separators and keep visible glyphs', () {
    const name = '株式会社\r\n右端確認';
    final columns = CompanySealPdf.verticalColumns(name);
    expect(columns.join(), '株式会社右端確認');
    expect(name, '株式会社\r\n右端確認');
    expect(CompanySealPdf.verticalColumns('足').join(), '足');
    expect(CompanySealPdf.verticalColumns('A B').join(), 'A B');
  });
  test('both real appendix builders keep saved parties and place generated/uploaded seals at the name end', () async {
    final font = await CompanySealPdf.loadFont();
    final directory = Platform.environment['SKO_SEAL_EDGE_OUTPUT_DIR'];
    const png = 'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAALUlEQVR4nO3OIQEAAAwEoetf+hdjBoWlVat9mYCAgICAgICAgICAgICAwHfgAIP/+kx2iamjAAAAAElFTkSuQmCC';
    final names = {'short': '株式会社足場', 'wide': '株式会社足場建設右端確認',
      'wrapped': List.filled(14, '株式会社右端確認').join(),
      'multiline': '株式会社\n右端確認', 'tiny': '足'};
    final manifest = <Map<String, dynamic>>[];
    for (final kind in ['order', 'acceptance']) {
      for (final item in names.entries) {
        for (final style in ['legacy', 'uploaded_png']) {
          // ignore: avoid_print
          print('rendering $kind-${item.key}-$style');
          final compactOrder = kind == 'order' && item.key == 'wrapped';
          final payload = <String, dynamic>{
            'version': 1, 'kind': kind, 'month': '2026-10',
            'issue_date': '2026-10-16', 'order_date': '2026-10-15',
            'period_start': '2026-10-01', 'period_end': '2026-10-31',
            'total_amount_yen': 110000, 'tax_amount_yen': 10000,
            'work_name': compactOrder ? List.filled(120, '工事').join() : '右端配置検証工事',
            'work_address': compactOrder ? List.filled(120, '現場').join() : '東京都墨田区1-2-3',
            'intro_text': compactOrder ? List.filled(150, '合意条件').join() : '下記条件で発注します。',
            'payment_conditions': '翌月末日払い',
            'acceptance_text': '注文条件を承諾します。',
            'notes': compactOrder ? List.filled(300, '特記').join() : '',
            'issuer': {'name': item.value, 'address': '東京都墨田区1-2-3',
              'corporate_number': '1234567890123', 'representative_name': '自社代表太郎'},
            'counterparty': {'name': '相手会社株式会社', 'address': '神奈川県横浜市4-5-6',
              'corporate_number': '9876543210987', 'representative_name': '相手代表次郎'},
            'company_seal_enabled': true,
            'company_seal_snapshot': style == 'legacy'
              ? {'version': 1, 'style': style, 'name': item.value}
              : {'version': 2, 'style': style, 'name': item.value,
                'company_id': '00000000-0000-0000-0000-000000000001',
                'png_version_id': '00000000-0000-0000-0000-000000000002',
                'png_base64': png,
                'png_sha256': '30ca1a5ef40b92ff14e0d5f9b4a2a9930ae2013a6cd9d7c4b636e3e70daa58fc'},
          };
          final original = jsonEncode(payload);
          final attachment = TradeDocumentAttachment.fromJson({'version': 1, 'payload': payload});
          final document = pw.Document(theme: pw.ThemeData.withFont(base: font, bold: font));
          if (kind == 'order') {
            await PaymentOrderPdf.append(document, attachment, regularFont: font, boldFont: font);
          } else {
            await InvoiceOrderAcceptancePdf.append(document, attachment, regularFont: font, boldFont: font);
          }
          final bytes = await document.save();
          expect(bytes.length, greaterThan(1000));
          expect(jsonEncode(payload), original);
          final name = '$kind-${item.key}-$style';
          if (directory != null) {
            Directory(directory).createSync(recursive: true);
            File('$directory/$name.pdf').writeAsBytesSync(bytes);
          }
          manifest.add({'file': '$name.pdf', 'kind': kind, 'name': item.value,
            'compact_order': compactOrder, 'representatives': ['自社代表太郎', '相手代表次郎']});
        }
      }
    }
    // Existing attachment validation still rejects an empty company name. The
    // layout helper itself must also stay within bounds when given legacy empties.
    expect(() => TradeDocumentAttachment.fromJson({'version': 1, 'payload': {
      'version': 1, 'kind': 'order', 'month': '2026-10',
      'issuer': {'name': ''}, 'counterparty': {'name': '相手会社'},
    }}), throwsStateError);
    for (final compact in [false, true]) {
      final size = compact ? 40.0 : 64.0;
      final fontSize = compact ? 8.0 : 11.0;
      expect(size - fontSize * 1.4, greaterThan(0));
      final document = pw.Document(theme: pw.ThemeData.withFont(base: font, bold: font));
      document.addPage(pw.Page(margin: const pw.EdgeInsets.all(48), build: (_) =>
        TradeDocumentCompanyNamePdf.build(name: '', textFont: font, fontSize: fontSize,
          labelWidth: 75, sealSize: size,
          seal: CompanySealPdf.build('空名検証', size: size, font: font, fallbackFont: font))));
      final file = 'helper-empty-${compact ? 'compact' : 'regular'}.pdf';
      final bytes = await document.save();
      if (directory != null) {
        File('$directory/$file').writeAsBytesSync(bytes);
      }
      manifest.add({'file': file, 'kind': 'helper', 'name': '',
        'compact_order': false, 'representatives': <String>[], 'empty': true});
    }
    if (directory != null) {
      File('$directory/manifest.json').writeAsStringSync(jsonEncode(manifest));
    }
  });
}
