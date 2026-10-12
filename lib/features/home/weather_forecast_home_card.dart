import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../international/language_controller.dart';
import 'home_information_card.dart';
import 'weather_forecast_card.dart';
import 'weather_forecast_controller.dart';

class WeatherForecastViewData {
  const WeatherForecastViewData({
    this.snapshot,
    this.loading = false,
    this.failed = false,
    this.addressFailed = false,
    this.companyAddressMissing = false,
    this.locationLabel,
    this.regionLabel,
    this.selectedDay = 0,
    this.baseDate,
  }) : assert(selectedDay >= 0 && selectedDay <= 2);
  final WeatherForecastSnapshot? snapshot;
  final bool loading;
  final bool failed;
  final bool addressFailed;
  final bool companyAddressMissing;
  final String? locationLabel;
  final String? regionLabel;
  final int selectedDay;
  final DateTime? baseDate;
  DateTime get date {
    final base = baseDate ?? DateTime.now();
    return DateTime(base.year, base.month, base.day + selectedDay);
  }

  WeatherForecastSnapshot? get forecast {
    final value = snapshot;
    return value != null &&
            value.forecastDate.year == date.year &&
            value.forecastDate.month == date.month &&
            value.forecastDate.day == date.day
        ? value
        : null;
  }

  String get temperatureLabel {
    final temperature = forecast?.currentTemperatureCelsius;
    if (temperature == null || !temperature.isFinite) {
      return SkoLanguageController.tr('未取得');
    }
    return '${temperature == temperature.roundToDouble() ? temperature.toStringAsFixed(0) : temperature}℃';
  }

  String get compactDayLabel =>
      selectedDay == 2 ? SkoLanguageController.tr('2日後') : dayLabel;
  String get dayLabel =>
      SkoLanguageController.tr(const ['今日', '明日', '明後日'][selectedDay]);
  String get status => addressFailed
      ? SkoLanguageController.tr('表示地域を取得できませんでした。')
      : companyAddressMissing
      ? SkoLanguageController.tr('会社住所を設定してください')
      : loading
      ? SkoLanguageController.tr('天気予報を取得中')
      : failed
      ? SkoLanguageController.tr('最新の天気予報を取得できませんでした。')
      : forecast?.currentSummary ?? SkoLanguageController.tr('天気予報は未取得です。');
}

class WeatherForecastHomeCard extends StatelessWidget {
  const WeatherForecastHomeCard({
    super.key,
    this.snapshot,
    this.loading = false,
    this.failed = false,
    this.companyAddressMissing = false,
    this.locationLabel,
    this.addressFailed = false,
    this.onRefresh,
    this.onOpenRadar,
    this.state,
    this.onSelectDay,
  });
  final WeatherForecastSnapshot? snapshot;
  final bool loading;
  final bool failed;
  final bool companyAddressMissing;
  final String? locationLabel;
  final bool addressFailed;
  final VoidCallback? onRefresh;
  final VoidCallback? onOpenRadar;
  final ValueListenable<WeatherForecastViewData>? state;
  final ValueChanged<int>? onSelectDay;

  WeatherForecastViewData get _initial => WeatherForecastViewData(
    snapshot: snapshot,
    loading: loading,
    failed: failed,
    companyAddressMissing: companyAddressMissing,
    locationLabel: locationLabel,
    addressFailed: addressFailed,
  );

  @override
  Widget build(BuildContext context) => state == null
      ? _card(context, _initial)
      : ValueListenableBuilder<WeatherForecastViewData>(
          valueListenable: state!,
          builder: (context, data, _) => _card(context, data),
        );

  Widget _card(
    BuildContext context,
    WeatherForecastViewData data,
  ) => HomeInformationCard(
    icon: Icons.cloud_outlined,
    title: SkoLanguageController.tr('天気予報'),
    showChevron: false,
    details:
        '${data.regionLabel ?? data.locationLabel ?? ''}${data.regionLabel == null && data.locationLabel == null ? '' : ' ／ '}${data.status}',
    footer: SkoLanguageController.tr('出勤前：自宅周辺 ／ 出勤後：現場周辺の天気を表示'),
    detailsTrailing: data.forecast == null
        ? null
        : SizedBox(
            width: 64,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                data.temperatureLabel,
                key: const ValueKey('weather-summary-temperature'),
                style: const TextStyle(fontSize: 11, height: 1.25),
              ),
            ),
          ),
    trailing: WeatherDayNavigation(
      data: data,
      onSelectDay: onSelectDay,
      compact: true,
    ),
    onTap: () => Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => WeatherForecastDetailPage(
          state: state,
          initial: data,
          onRefresh: onRefresh,
          onOpenRadar: onOpenRadar,
          onSelectDay: onSelectDay,
        ),
      ),
    ),
  );
}

class WeatherDayNavigation extends StatelessWidget {
  const WeatherDayNavigation({
    super.key,
    required this.data,
    this.onSelectDay,
    this.compact = false,
  });
  final WeatherForecastViewData data;
  final ValueChanged<int>? onSelectDay;
  final bool compact;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
    children: [
      IconButton(
        tooltip: SkoLanguageController.tr('前の日の天気'),
        constraints: BoxConstraints.tightFor(width: 44, height: 44),
        padding: EdgeInsets.zero,
        iconSize: compact ? 20 : 24,
        onPressed: data.selectedDay == 0 || onSelectDay == null
            ? null
            : () => onSelectDay!(data.selectedDay - 1),
        icon: const Icon(Icons.chevron_left),
      ),
      if (compact)
        SizedBox(
          width: 56,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  data.compactDayLabel,
                  style: const TextStyle(fontSize: 11, height: 1.1),
                ),
              ),
              Text(
                '${data.date.month}/${data.date.day}',
                style: const TextStyle(fontSize: 10, height: 1.1),
              ),
            ],
          ),
        )
      else
        Expanded(
          child: Text(
            '${data.dayLabel} ${data.date.month}/${data.date.day}',
            textAlign: TextAlign.center,
          ),
        ),
      IconButton(
        tooltip: SkoLanguageController.tr('次の日の天気'),
        constraints: BoxConstraints.tightFor(width: 44, height: 44),
        padding: EdgeInsets.zero,
        iconSize: compact ? 20 : 24,
        onPressed: data.selectedDay == 2 || onSelectDay == null
            ? null
            : () => onSelectDay!(data.selectedDay + 1),
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );
}

class WeatherForecastDetailPage extends StatelessWidget {
  const WeatherForecastDetailPage({
    super.key,
    this.state,
    this.initial = const WeatherForecastViewData(),
    this.onRefresh,
    this.onOpenRadar,
    this.onSelectDay,
  });
  final ValueListenable<WeatherForecastViewData>? state;
  final WeatherForecastViewData initial;
  final VoidCallback? onRefresh;
  final VoidCallback? onOpenRadar;
  final ValueChanged<int>? onSelectDay;
  @override
  Widget build(BuildContext context) => state == null
      ? _page(context, initial)
      : ValueListenableBuilder<WeatherForecastViewData>(
          valueListenable: state!,
          builder: (context, data, _) => _page(context, data),
        );
  Widget _page(BuildContext context, WeatherForecastViewData data) {
    final forecast = data.forecast;
    return Scaffold(
      appBar: AppBar(title: Text(SkoLanguageController.tr('天気予報'))),
      body: SingleChildScrollView(
        child: Column(
          children: [
            WeatherDayNavigation(data: data, onSelectDay: onSelectDay),
            WeatherForecastCard(
              locationLabel:
                  forecast?.locationLabel ?? data.locationLabel ?? data.status,
              hours: forecast?.hours ?? const [],
              currentSummary: forecast?.currentSummary,
              currentTemperatureCelsius: forecast?.currentTemperatureCelsius,
              rainApproachMessage: forecast?.rainApproachMessage,
              updatedAt: forecast?.updatedAt,
              sourceLabel: forecast?.sourceLabel,
              radarSupported: forecast?.radarSupported ?? false,
              onOpenRadar: onOpenRadar,
              onRefresh: onRefresh,
              loading: data.loading,
              failed: data.failed,
            ),
          ],
        ),
      ),
    );
  }
}
