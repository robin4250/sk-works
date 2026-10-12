import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/home/weather_forecast_controller.dart';
import 'package:sk_works/features/home/weather_forecast_policy.dart';

void main() {
  test('registered company, employee home and active site address rules', () {
    WeatherAddressSelection select({
      bool admin = false,
      bool working = false,
      String? company = '会社',
      String? home,
      String? site,
    }) => selectWeatherAddress(
      companyAddress: company,
      homeAddress: home,
      activeSiteAddress: site,
      working: working,
      isAdministrator: admin,
    );
    expect(
      select(admin: true, company: null).kind,
      WeatherAddressKind.unavailable,
    );
    expect(
      select(admin: true, home: '自宅', working: true, site: '現場').address,
      '会社',
    );
    expect(select(working: true, site: '現場').kind, WeatherAddressKind.company);
    expect(select(home: ' 自宅 ').address, '自宅');
    expect(select(home: '自宅', working: true, site: '現場').address, '現場');
    expect(
      select(home: '自宅', working: true, site: ' ').kind,
      WeatherAddressKind.unavailable,
    );
    expect(canChooseWeatherProvider(isMasterAdministrator: false), isFalse);
    expect(canChooseWeatherProvider(isMasterAdministrator: true), isTrue);
    expect(weatherForecastHours, [0, 3, 6, 9, 12, 15, 18, 21, 24]);
  });

  final day = DateTime(2026, 10, 12);
  WeatherForecastSnapshot data(String name) => WeatherForecastSnapshot(
    locationLabel: name,
    updatedAt: DateTime(2026, 10, 12),
    sourceLabel: '試験',
    forecastDate: DateTime(2026, 10, 12),
  );

  test(
    'old location response cannot overwrite a newly selected site',
    () async {
      final pending = <String, Completer<WeatherForecastSnapshot>>{};
      final controller = WeatherForecastController(
        fetch: (address, date) =>
            (pending[address.address!] = Completer<WeatherForecastSnapshot>())
                .future,
      );
      addTearDown(controller.dispose);
      final home = controller.refresh(
        const WeatherAddressSelection(WeatherAddressKind.home, '自宅'),
        date: day,
      );
      final site = controller.refresh(
        const WeatherAddressSelection(WeatherAddressKind.site, '現場'),
        date: day,
      );
      pending['現場']!.complete(data('現場'));
      await site;
      pending['自宅']!.complete(data('自宅'));
      await home;
      expect(controller.snapshot!.locationLabel, '現場');
      expect(controller.loading, isFalse);
    },
  );

  test(
    'retry failure keeps same-address data but new address clears it',
    () async {
      var fail = false;
      final controller = WeatherForecastController(
        fetch: (address, date) async {
          if (fail) throw StateError('unavailable');
          return data(address.address!);
        },
      );
      addTearDown(controller.dispose);
      const company = WeatherAddressSelection(WeatherAddressKind.company, '会社');
      await controller.refresh(company, date: day);
      fail = true;
      await controller.refresh(company, date: day);
      expect(controller.failed, isTrue);
      expect(controller.snapshot!.locationLabel, '会社');
      await controller.refresh(
        const WeatherAddressSelection(WeatherAddressKind.site, '現場'),
        date: day,
      );
      expect(controller.snapshot, isNull);
      expect(controller.failed, isTrue);
      await controller.refresh(
        const WeatherAddressSelection(WeatherAddressKind.unavailable, null),
        date: day,
      );
      expect(controller.loading, isFalse);
      expect(controller.failed, isFalse);
    },
  );

  test(
    'same-address old-day response cannot populate the selected new day',
    () async {
      final pending = <DateTime, Completer<WeatherForecastSnapshot>>{};
      final controller = WeatherForecastController(
        fetch: (address, date) =>
            (pending[date] = Completer<WeatherForecastSnapshot>()).future,
      );
      addTearDown(controller.dispose);
      const address = WeatherAddressSelection(WeatherAddressKind.home, '自宅');
      final tomorrow = DateTime(2026, 10, 13);
      final todayRequest = controller.refresh(address, date: day);
      final tomorrowRequest = controller.refresh(address, date: tomorrow);
      pending[tomorrow]!.complete(
        WeatherForecastSnapshot(
          locationLabel: '自宅',
          updatedAt: day,
          forecastDate: tomorrow,
          sourceLabel: '試験',
          currentSummary: '明日の試験データ',
        ),
      );
      await tomorrowRequest;
      pending[day]!.complete(data('自宅'));
      await todayRequest;
      expect(controller.snapshot!.forecastDate, tomorrow);
      expect(controller.snapshot!.currentSummary, '明日の試験データ');
      expect(controller.selectedDate, tomorrow);
      expect(controller.loading, isFalse);
    },
  );
}
