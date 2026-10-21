import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/shared/trade_document_template_settings_page.dart';
void main() {
  testWidgets('invoice and payment settings use same inline section and folded scope help', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ListView(children: [
      TradeDocumentTemplateSettingsSection(subjectKind: 'invoice'),
      TradeDocumentTemplateSettingsSection(subjectKind: 'payment_certificate'),
    ]))));
    expect(find.text('注文請書の自動生成・初期文'), findsOneWidget);
    expect(find.text('注文書の自動生成・初期文'), findsOneWidget);
    expect(find.text('？ 設定の反映範囲'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
