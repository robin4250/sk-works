import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sk_works/features/sites/site_page.dart';

void main() {
  testWidgets('site page shows sample sites', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: SitePage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('墨田区〇〇改修工事'), findsOneWidget);
    expect(find.text('江東区△△新築工事'), findsOneWidget);
    expect(find.text('現場登録'), findsOneWidget);
  });

  testWidgets('site page can filter active sites', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: SitePage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.widgetWithText(ChoiceChip, '進行中'));
    await tester.pump();

    expect(find.text('墨田区〇〇改修工事'), findsOneWidget);
    expect(find.text('江東区△△新築工事'), findsNothing);
  });
}
