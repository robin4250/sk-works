import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sk_works/main.dart';
import 'package:sk_works/features/chat/chat_cloud_page.dart';
import 'package:sk_works/features/home/friendly_home_content.dart';
import 'package:sk_works/widgets/sko_scroll_chrome.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SkoScrollChromeController.visible.value = true;
  });
  tearDown(() => SkoScrollChromeController.visible.value = true);

  Future<void> settleStartup(WidgetTester tester) async {
    // Drain the existing local-fallback asynchronous settings loads before
    // observing chrome-only work. No Supabase initialization or network fixture.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
  }

  for (final globalTheme in [false, true]) {
    testWidgets('chrome-only update avoids shell rebuild (global=$globalTheme)',
        (tester) async {
      await tester.pumpWidget(globalTheme
          ? const SkWorksApp(allowLocalFallback: true)
          : const MaterialApp(home: HomePage()));
      await settleStartup(tester);
      expect(find.byType(HomePage), findsOneWidget);
      expect(find.byType(FriendlyHomeContent), findsOneWidget);
      expect(find.byType(ChatCloudPage, skipOffstage: false), findsOneWidget);
      var homeBuilds = 0;
      var chatBuilds = 0;
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        previous?.call(element, builtOnce);
        if (element.widget is HomePage) homeBuilds++;
        if (element.widget is ChatCloudPage) chatBuilds++;
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previous);
      for (final visible in [false, true, false, true]) {
        SkoScrollChromeController.visible.value = visible;
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(homeBuilds, 0,
          reason: 'chrome-only updates must not rebuild the HomePage shell');
      if (!globalTheme) {
        expect(chatBuilds, 0,
            reason: 'shell chrome must not rebuild the offstage chat page');
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('ordinary layout refresh still rebuilds current Home data',
      (tester) async {
    await tester.pumpWidget(const SkWorksApp(allowLocalFallback: true));
    await settleStartup(tester);
    final content = find.byType(FriendlyHomeContent);
    expect(tester.widget<FriendlyHomeContent>(content).gridColumns, 2);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('sko_home_grid_columns', 4);
    await prefs.setStringList('sko_home_hidden_actions', ['weather_forecast']);
    final refresh = tester.widget<RefreshIndicator>(find.descendant(
        of: content, matching: find.byType(RefreshIndicator)));
    await refresh.onRefresh();
    await settleStartup(tester);
    expect(tester.widget<FriendlyHomeContent>(content).gridColumns, 4);
    expect(tester.widget<FriendlyHomeContent>(content).showWeatherForecast, false);
    expect(tester.takeException(), isNull);
  });
  testWidgets('fresh Home restores navigation after a hidden previous route',
      (tester) async {
    await tester.pumpWidget(const SkWorksApp(allowLocalFallback: true));
    await settleStartup(tester);
    SkoScrollChromeController.visible.value = false;
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(NavigationBar), findsNothing);
    // Recreating the app Navigator/Home also models identity-boundary teardown.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(SkoScrollChromeController.visible.value, false);
    await tester.pumpWidget(const SkWorksApp(allowLocalFallback: true));
    await settleStartup(tester);
    expect(find.byType(HomePage), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('ホーム'), findsOneWidget);
    expect(SkoScrollChromeController.visible.value, true);
    // Restoration is only for entry: later scroll hides and restores normally.
    SkoScrollChromeController.visible.value = false;
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(NavigationBar), findsNothing);
    SkoScrollChromeController.visible.value = true;
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

}
