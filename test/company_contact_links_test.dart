import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/companies/company_contact_links.dart';
import 'package:sk_works/features/companies/company_contact_parser.dart';

void main() {
  test(
    'notes preserve all text and link domestic, international and full-width numbers only',
    () {
      for (final text in [
        '担当 090-1234-5678\n代表 03(1234)5678',
        '電話 ０９０－１２３４－５６７８',
        '電話 +81 90-1234-5678',
      ]) {
        final parts = companyNoteParts(text);
        expect(parts.map((p) => p.text).join(), text);
        expect(parts.where((p) => p.uri != null), isNotEmpty);
        expect(
          parts.firstWhere((p) => p.uri != null).uri.toString(),
          'tel:09012345678',
        );
      }
      expect(
        companyNoteParts(
          '法人番号 0123456789012 日付 2026/01/02',
        ).where((p) => p.uri != null),
        isEmpty,
      );
      expect(companyPhoneUri('090abc12345678'), isNull);
      expect(
        companyAddressUri('東京都 江戸川区').queryParameters['query'],
        '東京都 江戸川区',
      );
    },
  );
  testWidgets('address and phone links open only after a tap', (tester) async {
    final opened = <Uri>[];
    final phone = companyPhoneUri('090-1234-5678')!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompanyContactValue(
            text: '090-1234-5678',
            uri: phone,
            onOpen: (uri) async => opened.add(uri),
          ),
        ),
      ),
    );
    expect(opened, isEmpty);
    await tester.tap(find.text('090-1234-5678'));
    await tester.pump();
    expect(opened, [phone]);
  });
  testWidgets(
    'a number inside notes opens its phone and keeps selection available',
    (tester) async {
      final opened = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CompanyNotesLinks(
              text: '090-1234-5678',
              onOpen: (uri) async => opened.add(uri),
            ),
          ),
        ),
      );
      expect(find.byType(SelectionArea), findsOneWidget);
      await tester.tap(find.text('090-1234-5678'));
      await tester.pump();
      expect(opened.map((uri) => uri.toString()), ['tel:09012345678']);
    },
  );
}
