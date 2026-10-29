import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/domain/trade_document_form_draft.dart';
import 'package:sk_works/features/shared/company_seal_pdf.dart';
import 'package:sk_works/features/shared/trade_document_form_pdf.dart';
import 'trade_document_form_draft_test.dart' show formBody;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('static label proof uses the unchanged registered font and preserves input', () async {
    final directory = Directory('build/trade-document-label-spacing')
      ..createSync(recursive: true);
    for (final kind in ['order', 'acceptance']) {
      final body = formBody()..['kind'] = kind;
      body['work_name'] = '入力　値は変更しない';
      final fields = TradeDocumentFormFields.empty().toJson();
      fields['rows'][0]['item'] = '第一明細';
      fields['rows'][8]['item'] = '第九明細';
      body['form_fields'] = fields;
      final before = jsonEncode(body);
      final font = await CompanySealPdf.loadFont();
      final document = pw.Document(theme: pw.ThemeData.withFont(base: font, bold: font));
      await TradeDocumentFormPdf.append(document, body, regularFont: font, boldFont: font);
      final bytes = await document.save();
      expect(jsonEncode(body), before);
      expect((body['form_fields']['rows'] as List).length, 9);
      expect(bytes.length, greaterThan(1000));
      File('${directory.path}/$kind.pdf').writeAsBytesSync(bytes);
    }
  });
}
