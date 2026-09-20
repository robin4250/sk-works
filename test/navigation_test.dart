import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sk_works/main.dart';

void main() {
  Future<void> pumpHome(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const SkWorksApp(allowLocalFallback: true));
    await tester.pump();
  }

  testWidgets('admin home routes to people module', (tester) async {
    await pumpHome(tester);

    expect(find.text('人員管理'), findsOneWidget);
    await tester.ensureVisible(find.text('人員管理'));
    await tester.pump();
    await tester.tap(find.text('人員管理'));
    await tester.pumpAndSettle();

    expect(find.text('新規登録'), findsOneWidget);
  });

  testWidgets('admin home routes to invoice module', (tester) async {
    await pumpHome(tester);

    expect(find.text('請求書'), findsOneWidget);
    await tester.ensureVisible(find.text('請求書'));
    await tester.pump();
    await tester.tap(find.text('請求書'));
    await tester.pumpAndSettle();

    expect(find.text('請求作成'), findsOneWidget);
  });

  testWidgets('admin home routes to settings module', (tester) async {
    await pumpHome(tester);

    expect(find.text('設定'), findsOneWidget);
    await tester.ensureVisible(find.text('設定'));
    await tester.pump();
    await tester.tap(find.text('設定'));
    await tester.pumpAndSettle();

    expect(find.text('設定を保存'), findsOneWidget);
  });

  testWidgets('footer exposes five primary destinations', (tester) async {
    await pumpHome(tester);

    expect(find.text('ホーム'), findsOneWidget);
    expect(find.text('出勤表'), findsOneWidget);
    expect(find.text('現場'), findsOneWidget);
    expect(find.text('チャット'), findsOneWidget);
    expect(find.text('メニュー'), findsOneWidget);
  });

  testWidgets('menu exposes secondary functions', (tester) async {
    await pumpHome(tester);

    await tester.tap(find.text('メニュー'));
    await tester.pumpAndSettle();

    expect(find.text('日報'), findsOneWidget);
    expect(find.text('プロフィール'), findsOneWidget);
    expect(find.text('ヘルプ'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('資格'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('資格'), findsOneWidget);
  });
}
