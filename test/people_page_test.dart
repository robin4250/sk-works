import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sk_works/features/people/people_page.dart';

void main() {
  testWidgets('people page shows sample employee and partner company', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const MaterialApp(home: PeoplePage()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('山田 太郎'), findsOneWidget);
    expect(find.text('株式会社サンプル工業'), findsOneWidget);
    expect(find.text('社員'), findsWidgets);
    expect(find.text('協力会社'), findsWidgets);
    expect(find.text('新規登録'), findsOneWidget);
  });

  testWidgets('people page filters by category', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const MaterialApp(home: PeoplePage()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.widgetWithText(ChoiceChip, '社員'));
    await tester.pump();

    expect(find.text('山田 太郎'), findsOneWidget);
    expect(find.text('株式会社サンプル工業'), findsNothing);
  });
}
