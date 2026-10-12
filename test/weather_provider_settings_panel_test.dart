import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/home/weather_provider_settings_panel.dart';
import 'package:sk_works/features/home/weather_attribution.dart';

class FakeWeatherSettings extends WeatherProviderSettingsRepository {
  FakeWeatherSettings() : super(SupabaseClient('https://example.invalid', 'test-public'));
  String value = 'openweather'; int saves = 0; bool fail = false;
  @override
  Future<String> load() async => value;
  @override
  Future<String> save(String provider) async {
    if (fail) { throw StateError('Unavailable'); }
    saves++; value = provider; return value;
  }
}
void main() {
  testWidgets('only master can switch and failed save preserves previous provider', (tester) async {
    final repo = FakeWeatherSettings(); var changes = 0;
    Future<void> pump(bool master) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: WeatherProviderSettingsPanel(
        isMaster: master, repository: repo, onChanged: () { changes++; }))));
      await tester.pumpAndSettle();
    }
    await pump(false); await tester.tap(find.text('Apple Weather (WeatherKit)')); await tester.pumpAndSettle();
    expect(repo.saves, 0);
    await pump(true); await tester.tap(find.text('Apple Weather (WeatherKit)')); await tester.pumpAndSettle();
    expect(repo.value, 'weatherkit'); expect(changes, 1);
    repo.fail = true; await tester.tap(find.text('OpenWeather')); await tester.pumpAndSettle();
    expect(repo.value, 'weatherkit'); expect(changes, 1);
    expect(find.text('天気設定を取得・保存できませんでした。'), findsOneWidget);
  });
  testWidgets('attribution stays visible and clickable at 320px text1.6', (tester) async {
    Uri? opened;
    await tester.pumpWidget(MaterialApp(home: MediaQuery(data: const MediaQueryData(
      size: Size(320, 600), textScaler: TextScaler.linear(1.6)), child: Scaffold(body: SizedBox(width: 320,
        child: WeatherAttribution(metadata: const {'name': 'OpenWeather', 'url': 'https://openweathermap.org/'},
          onOpen: (uri) { opened = uri; }))))));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('天気データの出典'));
    expect(opened?.host, 'openweathermap.org');
  });
}
