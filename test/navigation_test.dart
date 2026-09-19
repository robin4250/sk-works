import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sk_works/main.dart';

void main() {
  Future<void> openModule(
    WidgetTester tester,
    String menu,
    String expected,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const SkWorksApp());

    final menuFinder = find.text(menu);
    if (menuFinder.evaluate().isEmpty) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -500));
      await tester.pump();
    }

    expect(menuFinder, findsOneWidget);
    await tester.tap(menuFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text(expected), findsWidgets);
  }

  testWidgets('home routes to people module', (tester) async {
    await openModule(tester, '人員', '新規登録');
  });

  testWidgets('home routes to qualification module', (tester) async {
    await openModule(tester, '資格管理', '資格登録');
  });

  testWidgets('home routes to site module', (tester) async {
    await openModule(tester, '現場', '現場登録');
  });

  testWidgets('home routes to attendance module', (tester) async {
    await openModule(tester, '出勤表', '勤務を追加');
  });

  testWidgets('home routes to invoice module', (tester) async {
    await openModule(tester, '請求', '請求書を作る');
  });

  testWidgets('home routes to settings module', (tester) async {
    await openModule(tester, '設定', '設定を保存');
  });
}
