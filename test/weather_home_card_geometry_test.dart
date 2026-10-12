import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/home/friendly_home_content.dart';
import 'package:sk_works/features/home/home_attention_repository.dart';
import 'package:sk_works/features/home/home_information_card.dart';
import 'package:sk_works/features/home/home_membership_repository.dart';
import 'package:sk_works/features/home/weather_forecast_home_card.dart';
import 'package:sk_works/features/home/weather_forecast_card.dart';
import 'package:flutter/rendering.dart';
import 'package:sk_works/features/home/home_action_order_policy.dart';
import 'package:sk_works/features/home/weather_forecast_controller.dart';
import 'package:sk_works/international/language_controller.dart';
import 'package:sk_works/international/language_pack_registry.dart';

void main() {
  test('cached minute forecast hides past or stale notices and never appears on future days', () {
    final now = DateTime.utc(2026, 10, 12, 0, 1);
    final snapshot = WeatherForecastSnapshot(locationLabel: '会社周辺', updatedAt: now,
      forecastDate: DateTime(2026, 10, 12), sourceLabel: 'OpenWeather',
      rainForecastAt: DateTime.utc(2026, 10, 12, 0, 5),
      rainReferenceAt: DateTime.utc(2026, 10, 12), rainLocalHour: 9, rainLocalMinute: 5);
    final data = WeatherForecastViewData(baseDate: DateTime(2026, 10, 12), snapshot: snapshot);
    expect(data.rainApproachMessageAt(now), '09:05の降水予報');
    expect(data.rainApproachMessageAt(DateTime.utc(2026, 10, 12, 0, 5)), isNull);
    expect(data.rainApproachMessageAt(DateTime.utc(2026, 10, 12, 0, 16)), isNull);
    final future = WeatherForecastViewData(baseDate: DateTime(2026, 10, 11), selectedDay: 1, snapshot: snapshot);
    expect(future.rainApproachMessageAt(now), isNull);
  });

  test('future summary uses the selected forecast hour and never the current-day value', () {
    final data = WeatherForecastViewData(baseDate: DateTime(2026, 10, 12), selectedDay: 1,
      snapshot: WeatherForecastSnapshot(locationLabel: '現場', updatedAt: DateTime(2026, 10, 12),
        forecastDate: DateTime(2026, 10, 13), sourceLabel: 'OpenWeather',
        currentTemperatureCelsius: 99, currentSummary: '現在晴れ',
        forecastSummaryTemperatureCelsius: 18, forecastSummaryHour: 12, forecastSummary: '雨'));
    expect(data.temperatureLabel, '18℃');
    expect(data.summaryLabel, '12時の予報：雨');
    expect(data.status, isNot(contains('現在晴れ')));
  });
  testWidgets('live attribution stays inside the frame and clear of its reorder handle', (tester) async {
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
    final frame = tester.getRect(find.byKey(const ValueKey('weather-home-frame')));
    final source = tester.getRect(find.widgetWithText(TextButton, 'OpenWeather'));
    expect(frame.contains(handle.topLeft), isTrue);
    expect(frame.contains(handle.bottomRight), isTrue);
    expect(handle.overlaps(source), isFalse);
    expect(frame.contains(source.topLeft), isTrue);
    expect(frame.contains(source.bottomRight), isTrue);
    expect(tester.getSize(find.byType(WeatherForecastHomeCard)).height, frame.height);
    await tester.tap(find.text('OpenWeather')); await tester.pump();
    expect(opened.single.toString(), 'https://openweathermap.org/');
    expect(tester.takeException(), isNull);
  });

  testWidgets('weather keeps attention height with branding and readable footer in every state', (tester) async {
    tester.view.physicalSize = const Size(320, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final original = SkoLanguageController.pack.value;
    addTearDown(() => SkoLanguageController.pack.value = original);
    final live = WeatherForecastSnapshot(locationLabel: '会社周辺',
      forecastDate: DateTime(2026, 10, 12), updatedAt: DateTime(2026, 10, 12),
      sourceLabel: 'OpenWeather', currentSummary: '晴れ', currentTemperatureCelsius: 20,
      hours: const [WeatherForecastHour(hour: 12, summary: '晴れ', rainProbability: 20)]);
    for (final language in ['ja', 'en']) {
      SkoLanguageController.pack.value = LanguagePackRegistry.resolve(language);
      for (final scale in [1.0, 1.3, 1.6]) {
        for (final data in [
          WeatherForecastViewData(baseDate: DateTime(2026, 10, 12), companyAddressMissing: true),
          WeatherForecastViewData(baseDate: DateTime(2026, 10, 12), loading: true),
          WeatherForecastViewData(baseDate: DateTime(2026, 10, 12), addressFailed: true),
          WeatherForecastViewData(baseDate: DateTime(2026, 10, 12), failed: true),
          WeatherForecastViewData(baseDate: DateTime(2026, 10, 12), snapshot: live,
            attribution: const {'name': 'OpenWeather', 'url': 'https://openweathermap.org/'}),
        ]) {
          final state = ValueNotifier(data);
          await tester.pumpWidget(MaterialApp(home: Scaffold(body: MediaQuery(
            data: MediaQueryData(size: const Size(320, 1400), textScaler: TextScaler.linear(scale)),
            child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
              HomeInformationCard(key: const ValueKey('attention-baseline'), icon: Icons.info_outline,
                title: '要対応', details: '必要書類を登録してください', onTap: () {}),
              WeatherForecastHomeCard(state: state, onOpenAttribution: (_) {}, onSelectDay: (_) {}),
            ])),
          ))));
          await tester.pump();
          expect(tester.getSize(find.byType(WeatherForecastHomeCard)).height,
            tester.getSize(find.byKey(const ValueKey('attention-baseline'))).height);
          final footer = tester.renderObject<RenderParagraph>(find.byKey(const ValueKey('weather-location-explanation')));
          expect(footer.didExceedMaxLines, isFalse, reason: '$language / $scale');
          final info = tester.getRect(find.byKey(const ValueKey('weather-summary-precipitation')));
          expect(tester.getRect(find.byKey(const ValueKey('weather-location-explanation'))).top, greaterThanOrEqualTo(info.bottom));
          if (data.snapshot != null && language == 'ja') {
            expect(find.text('12時 20%'), findsOneWidget);
            expect(find.textContaining('20℃'), findsOneWidget);
            expect(find.text('最高 — / 最低 —'), findsOneWidget);
            for (final hour in [0, 3, 6, 9, 12, 15, 18, 21, 24]) {
              expect(find.byKey(ValueKey('weather-home-hour-$hour')), findsOneWidget);
            }
            expect(find.text('20%'), findsOneWidget);
          }
          expect(tester.takeException(), isNull, reason: '$language / $scale');
          await tester.pumpWidget(const SizedBox.shrink());
          state.dispose();
        }
      }
    }
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
    final frame = find.byKey(const ValueKey('weather-home-frame'));
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

      Finder frame(String text) => text == '天気予報' ? find.byKey(const ValueKey('weather-home-frame')) : find.ancestor(
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
        tester.getTopLeft(attention).dy,
        lessThan(tester.getTopLeft(find.text('本日の出勤')).dy),
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
