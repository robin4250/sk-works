import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sk_works/features/settings/settings_page.dart';

void main() {
  testWidgets('settings page shows company and invoice defaults', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('会社情報'), findsOneWidget);
    expect(find.text('請求設定'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'SKO'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('設定を保存'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('設定を保存'), findsOneWidget);
  });
}
