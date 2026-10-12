import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/home/friendly_home_content.dart';
import 'package:sk_works/features/home/home_attention_repository.dart';
import 'package:sk_works/features/home/home_information_card.dart';
import 'package:sk_works/features/home/home_membership_repository.dart';
import 'package:sk_works/features/home/weather_forecast_home_card.dart';
import 'package:sk_works/features/home/home_action_order_policy.dart';
import 'package:sk_works/features/home/weather_forecast_controller.dart';
import 'package:sk_works/international/language_controller.dart';
import 'package:sk_works/international/language_pack_registry.dart';

void main() {
  test('future summary uses the selected forecast hour and never today's current value', () {
    final data = WeatherForecastViewData(baseDate: DateTime(2026, 10, 12), selectedDay: 1,
      snapshot: WeatherForecastSnapshot(locationLabel: '現場', updatedAt: DateTime(2026, 10, 12),
        forecastDate: DateTime(2026, 10, 13), sourceLabel: 'OpenWeather',
        currentTemperatureCelsius: 99, currentSummary: '現在晴れ',
        forecastSummaryTemperatureCelsius: 18, forecastSummaryHour: 12, forecastSummary: '雨'));
    expect(data.temperatureLabel, '18℃');
    expect(data.summaryLabel, '12時の予報：雨');
    expect(data.status, isNot(contains('現在晴れ')));
  });
  testWidgets('live attribution stays outside the frame and clear of its reorder handle', (tester) async {
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = ValueNotifier(WeatherForecastViewData(baseDate: DateTime(2026, 10, 12),
      snapshot: WeatherForecastSnapshot(locationLabel: '会社周辺', updatedAt: DateTime(2026, 10, 12),
        forecastDate: DateTime(2026, 10, 12), sourceLabel: 'OpenWeather', currentTemperatureCelsius: 20),
      attribution: const {'name': 'OpenWeather', 'url': 'https://openweathermap.org/'}));
    addTearDown(state.dispose);
    final opened = <Uri>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MediaQuery(
      data: const MediaQueryData(size: Size(320, 1000), textScaler: TextScaler.linear(1.3)),
      child: FriendlyHomeContent(
        identity: const HomeIdentity(role: 'worker', companyName: '会社', displayName: '本人'),
        requiredDocumentAttention: const RequiredDocumentAttention(missingCount: 0, missingNames: [], needsLicense: false, needsQualification: false),
        moduleEnabled: (_) => true, showAttendanceReport: false, showTodayAttendance: false,
        weatherCard: WeatherForecastHomeCard(state: state, onOpenAttribution: opened.add, onSelectDay: (_) {}),
        onOpen: (_) async {}, onRefresh: () async {}, onReorderAction: (_, _) async {},
      ),
    ))));
    await tester.pump();
    final handle = tester.getRect(find.byKey(const ValueKey('home-reorder-weather_forecast')));
    final frame = tester.getRect(find.byType(HomeInformationCard));
    final source = tester.getRect(find.widgetWithText(TextButton, '天気データの出典'));
    expect(frame.contains(handle.topLeft), isTrue);
    expect(frame.contains(handle.bottomRight), isTrue);
    expect(handle.overlaps(source), isFalse);
    await tester.tap(find.text('天気データの出典')); await tester.pump();
    expect(opened.single.toString(), 'https://openweathermap.org/');
    expect(tester.takeException(), isNull);
  });

  testWidgets('weather reorder handle does not steal the next-day button', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = ValueNotifier(
      WeatherForecastViewData(baseDate: DateTime(2026, 10, 12)),
    );
    addTearDown(state.dispose);
    final reordered = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(size: Size(320, 1000), textScaler: TextScaler.linear(1.3)),
            child: FriendlyHomeContent(
              identity: const HomeIdentity(
                role: 'worker',
                companyName: '会社',
                displayName: '本人',
              ),
              requiredDocumentAttention: const RequiredDocumentAttention(
                missingCount: 0,
                missingNames: [],
                needsLicense: false,
                needsQualification: false,
              ),
              moduleEnabled: (_) => true,
              showAttendanceReport: false,
              visibleHomeKeys: const {'attendance_today'},
              weatherCard: WeatherForecastHomeCard(
                state: state,
                onSelectDay: (day) => state.value = WeatherForecastViewData(
                  baseDate: DateTime(2026, 10, 12),
                  selectedDay: day,
                ),
              ),
              onOpen: (_) async {},
              onRefresh: () async {},
              onReorderAction: (from, to) async => reordered.add('$from:$to'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final handle = find.byKey(const ValueKey('home-reorder-weather_forecast'));
    final next = find.byTooltip('次の日の天気');
    expect(tester.getRect(handle).overlaps(tester.getRect(next)), isFalse);
    final frame = find.ancestor(of: find.text('天気予報'), matching: find.byType(HomeInformationCard));
    final previous = find.byTooltip('前の日の天気');
    final cardRect = tester.getRect(frame);
    expect(tester.getRect(previous).left - cardRect.left, lessThanOrEqualTo(6));
    expect(cardRect.right - tester.getRect(next).right, lessThanOrEqualTo(16));
    expect(tester.getRect(previous).overlaps(tester.getRect(handle)), isFalse);
    expect((tester.getCenter(find.text('今日 10/12')).dx - cardRect.center.dx).abs(), lessThanOrEqualTo(16));

    await tester.tap(next);
    await tester.pump();
    expect(state.value.selectedDay, 1);
    expect(reordered, isEmpty);
    final target = find.ancestor(
      of: find.text('本日の出勤'),
      matching: find.byWidgetPredicate(
        (widget) => widget is DragTarget<String>,
      ),
    );
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 650));
    await gesture.moveTo(tester.getCenter(target));
    await tester.pump(const Duration(milliseconds: 150));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 150));
    expect(reordered, ['weather_forecast:attendance_today']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test(
    'settings menu reorder retains weather defaults and the attention slot',
    () {
      final saved = [
        'attendance_verify',
        'attendance_today',
        'profile',
        'documents',
      ];
      final menu = [
        'attendance_verify',
        'attendance_today',
        'weather_forecast',
        'profile',
        'documents',
      ];
      final reordered = reorderHomeMenuActions(saved, menu, 4, 3);
      expect(reordered, [
        'attendance_verify',
        'attendance_today',
        'weather_forecast',
        'home_attention',
        'documents',
        'profile',
      ]);
      final custom = ['home_attention', ...saved, 'weather_forecast'];
      final customMenu = normalizeHomeActionOrder(custom, [
        ...menu,
        'home_attention',
      ]).where(menu.contains).toList();
      final customReordered = reorderHomeMenuActions(custom, customMenu, 3, 2);
      expect(customReordered.first, 'home_attention');
      expect(customReordered.last, 'weather_forecast');
    },
  );
  test(
    'first unrelated reorder preserves inserted weather and attention positions',
    () {
      final available = [
        'attendance_verify',
        'attendance_today',
        'profile',
        'documents',
        'weather_forecast',
        'home_attention',
      ];
      final order = normalizeHomeActionOrder([
        'attendance_verify',
        'attendance_today',
        'profile',
        'documents',
      ], available);
      expect(order, [
        'attendance_verify',
        'attendance_today',
        'weather_forecast',
        'home_attention',
        'profile',
        'documents',
      ]);
      final moved = order.removeAt(order.indexOf('documents'));
      order.insert(order.indexOf('profile'), moved);
      expect(normalizeHomeActionOrder(order, available).sublist(0, 4), [
        'attendance_verify',
        'attendance_today',
        'weather_forecast',
        'home_attention',
      ]);
    },
  );

  testWidgets(
    'three day arrows share selection with reactive detail; English small footer remains readable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final original = SkoLanguageController.pack.value;
      SkoLanguageController.pack.value = LanguagePackRegistry.resolve('en');
      addTearDown(() => SkoLanguageController.pack.value = original);
      final base = DateTime(2026, 10, 12);
      final state = ValueNotifier(
        WeatherForecastViewData(
          baseDate: base,
          locationLabel: 'Old area',
          snapshot: WeatherForecastSnapshot(
            locationLabel: 'Old area',
            updatedAt: base,
            forecastDate: base,
            sourceLabel: 'Fixture',
            currentSummary: 'Today only',
            currentTemperatureCelsius: 21.5,
          ),
        ),
      );
      addTearDown(state.dispose);
      void select(int day) {
        state.value = WeatherForecastViewData(
          baseDate: base,
          selectedDay: day,
          locationLabel: 'New area',
        );
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
              child: WeatherForecastHomeCard(
                state: state,
                onSelectDay: select,
                onRefresh: () => state.value = WeatherForecastViewData(
                  baseDate: base,
                  selectedDay: state.value.selectedDay,
                  locationLabel: 'Refreshed area',
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.textContaining('21.5℃').hitTestable(), findsOneWidget);
      final description = find.text('Before: home / During: site');
      expect(description.hitTestable(), findsOneWidget);
      final text = tester.widget<Text>(description);
      final painter = TextPainter(
        text: TextSpan(text: text.data, style: text.style),
        maxLines: 2,
        textScaler: const TextScaler.linear(1.3),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: tester.getSize(description).width);
      expect(painter.didExceedMaxLines, isFalse);
      final previous = tester.widget<IconButton>(
        find.byWidgetPredicate((widget) => widget is IconButton && widget.tooltip == 'Previous day weather'),
      );
      expect(previous.onPressed, isNull);
      await tester.tap(find.byTooltip('Next day weather'));
      await tester.pump();
      expect(state.value.selectedDay, 1);
      expect(find.textContaining('21.5℃'), findsNothing);
      expect(find.textContaining('Today only'), findsNothing);
      expect(find.text('Tomorrow 10/13'), findsOneWidget);
      state.value = WeatherForecastViewData(
        baseDate: base,
        selectedDay: 1,
        locationLabel: 'New area',
        snapshot: WeatherForecastSnapshot(
          locationLabel: 'Wrong day area',
          updatedAt: base,
          forecastDate: base,
          sourceLabel: 'Fixture',
          currentSummary: 'Wrong day weather',
          currentTemperatureCelsius: 99,
        ),
      );
      await tester.pump();
      expect(find.textContaining('99℃'), findsNothing);
      expect(find.textContaining('Wrong day weather'), findsNothing);

      await tester.tap(find.text('Forecast'));
      await tester.pumpAndSettle();
      expect(find.text('Tomorrow 10/13'), findsOneWidget);
      await tester.tap(find.byTooltip('Next day weather').hitTestable());
      await tester.pump();
      expect(state.value.selectedDay, 2);
      expect(find.text('Day after tomorrow 10/14'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate((widget) => widget is IconButton && widget.tooltip == 'Next day weather').hitTestable(),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('Refresh weather'));
      await tester.pump();
      expect(find.text('Refreshed area'), findsOneWidget);
      expect(find.text('Old area'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('In 2 days 10/14'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'weather matches attention geometry and default placement; toggle and order work',
    (tester) async {
      tester.view.physicalSize = const Size(320, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Future<void> open({
        bool visible = true,
        List<String> order = const [],
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
                child: FriendlyHomeContent(
                  identity: const HomeIdentity(
                    role: 'worker',
                    companyName: '会社',
                    displayName: '本人',
                  ),
                  requiredDocumentAttention: const RequiredDocumentAttention(
                    missingCount: 1,
                    missingNames: [],
                    needsLicense: false,
                    needsQualification: false,
                    notificationPreviews: ['申請の確認が必要です', '期限がある書類', '未対応の通知'],
                  ),
                  moduleEnabled: (_) => true,
                  showAttendanceReport: false,
                  visibleHomeKeys: const {'attendance_today'},
                  weatherCard: const WeatherForecastHomeCard(
                    companyAddressMissing: true,
                  ),
                  showWeatherForecast: visible,
                  actionOrder: order,
                  onOpen: (_) async {},
                  onRefresh: () async {},
                ),
              ),
            ),
          ),
        );
        await tester.pump();
      }

      Finder frame(String text) => find.ancestor(
        of: find.text(text),
        matching: find.byType(HomeInformationCard),
      );
      await open();
      final weather = frame('天気予報');
      final attention = frame('要対応');
      expect(tester.getSize(weather), tester.getSize(attention));
      expect(
        tester.getTopLeft(find.text('本日の出勤')).dy,
        lessThan(tester.getTopLeft(weather).dy),
      );
      expect(
        tester.getTopLeft(weather).dy,
        lessThan(tester.getTopLeft(attention).dy),
      );
      expect(find.text('申請の確認が必要です\n期限がある書類\n未対応の通知'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await open(
        order: ['weather_forecast', 'attendance_today', 'home_attention'],
      );
      expect(
        tester.getTopLeft(frame('天気予報')).dy,
        lessThan(tester.getTopLeft(find.text('本日の出勤')).dy),
      );
      await open(visible: false);
      expect(find.text('天気予報'), findsNothing);
      expect(find.text('要対応'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('address failure is not described as an unregistered company', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: WeatherForecastHomeCard(addressFailed: true)),
      ),
    );
    expect(find.textContaining('表示地域を取得できませんでした。'), findsOneWidget);
    expect(find.textContaining('会社住所を設定してください'), findsNothing);
    await tester.tap(find.text('天気予報'));
    await tester.pumpAndSettle();
    expect(find.text('表示地域を取得できませんでした。'), findsOneWidget);
    expect(find.text('天気予報は未取得です。'), findsOneWidget);
  });
}
