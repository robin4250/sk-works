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
        find.byTooltip('Previous day weather'),
      );
      expect(previous.onPressed, isNull);
      await tester.tap(find.byTooltip('Next day weather'));
      await tester.pump();
      expect(state.value.selectedDay, 1);
      expect(find.textContaining('Today only'), findsNothing);
      expect(find.text('Tomorrow'), findsOneWidget);
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
              find.byTooltip('Next day weather').hitTestable(),
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
      expect(find.text('In 2 days'), findsOneWidget);
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
