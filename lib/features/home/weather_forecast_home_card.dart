import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../international/language_controller.dart';
import 'home_information_card.dart';
import 'weather_attribution.dart';
import 'weather_forecast_card.dart';
import 'weather_forecast_controller.dart';

class WeatherForecastViewData {
  const WeatherForecastViewData({
    this.snapshot,
    this.attribution = const {},
    this.radarUri,
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
  final Map<String, dynamic> attribution;
  final Uri? radarUri;
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
    final temperature = summaryTemperature;
    if (temperature == null || !temperature.isFinite) {
      return SkoLanguageController.tr('未取得');
    }
    return '${temperature == temperature.roundToDouble() ? temperature.toStringAsFixed(0) : temperature}℃';
  }

  double? get summaryTemperature => selectedDay == 0 && forecast?.currentTemperatureCelsius != null
      ? forecast?.currentTemperatureCelsius : forecast?.forecastSummaryTemperatureCelsius;
  String? get summaryLabel {
    final value = forecast;
    if (value == null) {
      return null;
    }
    if (selectedDay == 0 && value.currentSummary != null) {
      return value.currentSummary;
    }
    if (value.forecastSummaryHour != null && value.forecastSummary != null) {
      return '${SkoLanguageController.trParams('{hour}時の予報', {'hour': value.forecastSummaryHour})}：${value.forecastSummary}';
    }
    return null;
  }

  String? rainApproachMessageAt(DateTime now) {
    final value = forecast;
    if (value == null || selectedDay != 0) {
      return null;
    }
    final at = value.rainForecastAt;
    final reference = value.rainReferenceAt;
    final hour = value.rainLocalHour, minute = value.rainLocalMinute;
    if (at == null || reference == null || hour == null || minute == null ||
        !at.isAfter(now) || at.isAfter(now.add(const Duration(minutes: 60))) ||
        reference.isBefore(now.subtract(const Duration(minutes: 15))) ||
        reference.isAfter(now.add(const Duration(minutes: 1))) ||
        hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return null;
    }
    return SkoLanguageController.trParams('{hour}:{minute}の降水予報', {
      'hour': hour.toString().padLeft(2, '0'),
      'minute': minute.toString().padLeft(2, '0'),
    });
  }
  String? get rainApproachMessage => rainApproachMessageAt(DateTime.now());
  String? get summaryWithRain {
    final summary = summaryLabel;
    final rain = rainApproachMessage;
    return rain == null ? summary : summary == null ? rain : '$summary ／ $rain';
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
      : summaryWithRain ?? SkoLanguageController.tr('天気予報は未取得です。');
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
    this.onOpenAttribution,
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
  final ValueChanged<Uri>? onOpenAttribution;
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

  Widget _card(BuildContext context, WeatherForecastViewData data) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      key: const ValueKey('weather-home-frame'), margin: EdgeInsets.zero,
      color: colors.surface,
      shape: RoundedRectangleBorder(side: BorderSide(color: colors.primary, width: 1.5), borderRadius: BorderRadius.circular(16)),
      child: InkWell(borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => WeatherForecastDetailPage(
          state: state, initial: data, onRefresh: onRefresh, onOpenRadar: onOpenRadar,
          onOpenAttribution: onOpenAttribution, onSelectDay: onSelectDay))),
        child: SizedBox(height: HomeInformationCard.heightFor(context),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Column(children: [
              SizedBox(height: 44, child: Stack(clipBehavior: Clip.none, children: [
                Positioned(left: -6, top: 0, width: 44, height: 44, child: _WeatherHomeDayArrow(data: data, onSelectDay: onSelectDay, backward: true)),
                Align(alignment: Alignment.centerRight, child: _WeatherHomeDayArrow(data: data, onSelectDay: onSelectDay, backward: false)),
                Center(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 72), child: FittedBox(fit: BoxFit.scaleDown,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('${data.compactDayLabel} ${data.date.month}/${data.date.day}', style: const TextStyle(fontSize: 11, height: 1.1)),
                    if (data.forecast != null && data.attribution.isNotEmpty && onOpenAttribution != null)
                      WeatherAttribution(metadata: data.attribution, onOpen: onOpenAttribution!, compact: true)
                    else Text(SkoLanguageController.tr('天気予報'), style: const TextStyle(fontSize: 9, height: 1.1)),
                  ])))),
              ])),
              Expanded(child: _WeatherReferenceInformation(data: data, onOpenRadar: onOpenRadar)),
            ])),
        )),
    );
  }
}

class _WeatherReferenceInformation extends StatelessWidget {
  const _WeatherReferenceInformation({required this.data, this.onOpenRadar});
  final WeatherForecastViewData data;
  final VoidCallback? onOpenRadar;
  WeatherForecastHour? at(int hour) {
    final matches = data.forecast?.hours.where((value) => value.hour == hour).toList();
    return matches != null && matches.length == 1 ? matches.single : null;
  }
  IconData get summaryIcon {
    final value = data.forecast;
    if (value == null) return Icons.help_outline;
    if (data.selectedDay == 0 && value.currentSummary != null) {
      final currentIcons = <String, IconData>{
        '晴れ': Icons.wb_sunny_outlined,
        '曇り': Icons.cloud_outlined,
        '雷': Icons.thunderstorm_outlined,
        '雨': Icons.water_drop_outlined,
        '雪': Icons.ac_unit,
        '霧': Icons.blur_on,
      };
      for (final entry in currentIcons.entries) {
        if (SkoLanguageController.tr(entry.key) == value.currentSummary) return entry.value;
      }
      return Icons.help_outline;
    }
    return at(value.forecastSummaryHour ?? 12)?.icon ?? Icons.help_outline;
  }
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final forecast = data.forecast;
    final region = data.regionLabel ?? forecast?.locationLabel ?? data.locationLabel ?? data.status;
    final summaryHour = forecast?.forecastSummaryHour ?? 12;
    final chance = at(summaryHour)?.rainProbability;
    final radarAvailable = forecast?.radarSupported == true && onOpenRadar != null;
    return Column(children: [
      Expanded(flex: 4, child: Row(children: [
        Icon(summaryIcon, key: const ValueKey('weather-summary-icon'), size: 25, color: colors.primary),
        const SizedBox(width: 4),
        Expanded(flex: 4, child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(region, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, height: 1.1)),
          FittedBox(fit: BoxFit.scaleDown, child: Text('${SkoLanguageController.tr('最高')} — / ${SkoLanguageController.tr('最低')} —',
            key: const ValueKey('weather-daily-extrema'), style: const TextStyle(fontSize: 9, height: 1.1))),
          Text(forecast == null ? data.status : '${data.summaryLabel ?? SkoLanguageController.tr('未取得')} ${data.temperatureLabel}',
            key: const ValueKey('weather-summary-temperature'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 8, height: 1.1)),
        ])),
        Expanded(flex: 3, child: FittedBox(fit: BoxFit.scaleDown, child: Column(children: [
          Text(SkoLanguageController.tr('降水確率'), style: const TextStyle(fontSize: 9, height: 1.1)),
          Text(chance == null ? '—' : '$summaryHour${SkoLanguageController.tr('時')} $chance%',
            key: const ValueKey('weather-summary-precipitation'), style: TextStyle(fontSize: 12, height: 1.1, color: colors.primary)),
        ]))),
        if (radarAvailable) SizedBox(width: 58, child: TextButton(onPressed: onOpenRadar,
          style: TextButton.styleFrom(padding: const EdgeInsets.all(2), minimumSize: const Size(44, 32)),
          child: FittedBox(fit: BoxFit.scaleDown, child: Text(SkoLanguageController.tr('雨雲レーダー'), style: const TextStyle(fontSize: 9))))),
      ])),
      Expanded(flex: 4, child: Row(children: List.generate(9, (index) {
        final hour = index * 3;
        final value = at(hour);
        return Expanded(child: Semantics(label: '$hour${SkoLanguageController.tr('時')} ${value?.summary ?? SkoLanguageController.tr('未取得')}',
          child: FittedBox(fit: BoxFit.scaleDown, child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$hour${SkoLanguageController.tr('時')}', style: const TextStyle(fontSize: 8, height: 1.1)),
            Icon(value?.icon ?? Icons.help_outline, key: ValueKey('weather-home-hour-$hour'), size: 15, color: colors.primary),
            Text(value?.rainProbability == null ? '—' : '${value?.rainProbability}%', style: const TextStyle(fontSize: 8, height: 1.1)),
          ]))));
      }))),
      if (data.rainApproachMessage != null) FittedBox(fit: BoxFit.scaleDown, child: Text(data.rainApproachMessage!, style: const TextStyle(fontSize: 8))),
      FittedBox(fit: BoxFit.scaleDown, child: Text(SkoLanguageController.tr('出勤前：自宅周辺 ／ 出勤後：現場周辺の天気を表示'),
        key: const ValueKey('weather-location-explanation'), style: const TextStyle(fontSize: 8, height: 1.1))),
    ]);
  }
}

class _WeatherHomeDayArrow extends StatelessWidget {
  const _WeatherHomeDayArrow({required this.data, required this.backward, this.onSelectDay});
  final WeatherForecastViewData data;
  final bool backward;
  final ValueChanged<int>? onSelectDay;
  @override
  Widget build(BuildContext context) {
    final allowed = onSelectDay != null && (backward ? data.selectedDay > 0 : data.selectedDay < 2);
    final scheme = Theme.of(context).colorScheme;
    final color = scheme.primary;
    return GestureDetector(
      excludeFromSemantics: true,
      onTap: allowed ? null : () {},
      child: IconButton(
        tooltip: SkoLanguageController.tr(backward ? '前の日の天気' : '次の日の天気'),
        constraints: const BoxConstraints.tightFor(width: 44, height: 44),
        padding: EdgeInsets.zero,
        onPressed: allowed ? () => onSelectDay!(data.selectedDay + (backward ? -1 : 1)) : null,
        icon: Icon(backward ? Icons.arrow_left : Icons.arrow_right, color: allowed ? color : color.withValues(alpha: 0.38)),
      ),
    );
  }
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
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${data.date.month}/${data.date.day}',
                  maxLines: 1,
                  softWrap: false,
                  style: const TextStyle(fontSize: 10, height: 1.1),
                ),
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
    this.onOpenAttribution,
    this.onSelectDay,
  });
  final ValueListenable<WeatherForecastViewData>? state;
  final WeatherForecastViewData initial;
  final VoidCallback? onRefresh;
  final VoidCallback? onOpenRadar;
  final ValueChanged<Uri>? onOpenAttribution;
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
              currentSummary: data.summaryLabel,
              currentTemperatureCelsius: data.summaryTemperature,
              rainApproachMessage: data.rainApproachMessage,
              updatedAt: forecast?.updatedAt,
              sourceLabel: forecast?.sourceLabel,
              radarSupported: forecast?.radarSupported ?? false,
              onOpenRadar: onOpenRadar,
              onRefresh: onRefresh,
              loading: data.loading,
              failed: data.failed,
            ),
            if (forecast != null && data.attribution.isNotEmpty && onOpenAttribution != null)
              WeatherAttribution(metadata: data.attribution, onOpen: onOpenAttribution!),
          ],
        ),
      ),
    );
  }
}
