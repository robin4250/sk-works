import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sk_works/main.dart';

void main() {
  Future<void> pumpIphone(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double textScale = 1.6,
  }) async {
    SharedPreferences.setMockInitialValues({});

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;

    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    await tester.pumpWidget(const SkWorksApp());
    await tester.pumpAndSettle();
  }

  testWidgets('main home fits iPhone portrait with large text', (tester) async {
    await pumpIphone(tester);

    expect(find.text('SKO'), findsWidgets);
    expect(find.text('本日の出勤'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('five-tab navigation remains usable with large text', (
    tester,
  ) async {
    await pumpIphone(tester, size: const Size(375, 812), textScale: 1.6);

    expect(find.text('ホーム'), findsOneWidget);
    expect(find.text('出勤表'), findsOneWidget);
    expect(find.text('現場'), findsOneWidget);
    expect(find.text('チャット'), findsOneWidget);
    expect(find.text('メニュー'), findsOneWidget);

    await tester.tap(find.text('メニュー'));
    await tester.pumpAndSettle();

    expect(find.text('プロフィール'), findsOneWidget);
    expect(find.text('ヘルプ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact iPhone portrait does not overflow home', (tester) async {
    await pumpIphone(
      tester,
      size: const Size(320, 568),
      textScale: 1.3,
    );

    expect(find.text('本日の出勤'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
