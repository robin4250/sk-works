import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/home/weather_forecast_card.dart';

void main() {
  Widget host(Widget card) => MaterialApp(
    theme: ThemeData(colorSchemeSeed: Colors.blue),
    home: Scaffold(
      body: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: SingleChildScrollView(child: card),
      ),
    ),
  );

  testWidgets(
    'small card preserves all nine hourly slots and uses theme colors',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final days = List.generate(
        9,
        (i) => WeatherForecastHour(
          hour: i * 3,
          summary: '晴れ時々くもり、所により雨',
          temperatureCelsius: 22,
          rainProbability: 20,
        ),
      );
      await tester.pumpWidget(
        host(
          WeatherForecastCard(
            locationLabel: '東京都すみだ地区の長い地域表示',
            hours: days,
            updatedAt: DateTime(2026, 10, 12, 9, 5),
            sourceLabel: 'テスト用情報源',
          ),
        ),
      );
      expect(find.text('更新 10/12 09:05'), findsOneWidget);
      expect(find.text('0時').hitTestable(), findsOneWidget);
      final scroll = find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal,
      );
      await tester.drag(scroll, const Offset(-1300, 0));
      await tester.pumpAndSettle();
      expect(find.text('24時').hitTestable(), findsOneWidget);
      final icon = tester.widget<Icon>(find.byIcon(Icons.cloud_outlined).first);
      final context = tester.element(find.byType(WeatherForecastCard));
      expect(icon.color, Theme.of(context).colorScheme.primary);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('missing values are not shown as zero, refresh and help work', (
    tester,
  ) async {
    var refreshes = 0;
    await tester.pumpWidget(
      host(
        WeatherForecastCard(
          locationLabel: '',
          hours: [WeatherForecastHour(hour: 0, summary: '')],
          onRefresh: () => refreshes++,
        ),
      ),
    );
    expect(find.text('地域未設定'), findsOneWidget);
    expect(find.text('未取得'), findsWidgets);
    expect(find.text('降水 未取得'), findsNWidgets(9));
    await tester.tap(find.byTooltip('天気予報を更新'));
    expect(refreshes, 1);
    await tester.tap(find.byTooltip('天気予報のヘルプ'));
    await tester.pumpAndSettle();
    expect(find.text(WeatherForecastCard.helpText), findsOneWidget);
    await tester.tap(find.text('閉じる'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('loading disables refresh and failure retains dated forecast', (
    tester,
  ) async {
    var refreshes = 0;
    final forecast = [WeatherForecastHour(hour: 0, summary: 'くもり')];
    await tester.pumpWidget(
      host(
        WeatherForecastCard(
          locationLabel: '選択地域',
          hours: forecast,
          loading: true,
          onRefresh: () => refreshes++,
        ),
      ),
    );
    await tester.tap(find.byTooltip('天気予報を更新'));
    expect(refreshes, 0);
    expect(find.text('天気予報を取得中'), findsOneWidget);
    await tester.pumpWidget(
      host(
        WeatherForecastCard(
          locationLabel: '選択地域',
          hours: forecast,
          updatedAt: DateTime(2026, 10, 12, 8),
          failed: true,
          onRefresh: () => refreshes++,
        ),
      ),
    );
    expect(find.text('最新の天気予報を取得できませんでした。'), findsOneWidget);
    expect(find.text('くもり'), findsOneWidget);
    expect(find.text('更新 10/12 08:00'), findsOneWidget);
    await tester.tap(find.byTooltip('天気予報を更新'));
    expect(refreshes, 1);
    expect(tester.takeException(), isNull);
  });
}
