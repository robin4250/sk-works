import 'package:flutter/material.dart';

import '../../international/language_controller.dart';
import 'weather_forecast_policy.dart';

/// Clear and rain symbols use fixed colors in both compact and detailed forecasts.
Color weatherConditionIconColor(IconData icon, ColorScheme colors) {
  if (icon == Icons.wb_sunny || icon == Icons.wb_sunny_outlined) {
    return Colors.orange;
  }
  if (icon == Icons.umbrella || icon == Icons.umbrella_outlined) {
    return Colors.blue;
  }
  return colors.primary;
}

/// Display-only forecast data. Its source and location are supplied by the caller.
class WeatherForecastHour {
  const WeatherForecastHour({
    required this.hour,
    required this.summary,
    this.icon = Icons.cloud_outlined,
    this.temperatureCelsius,
    this.rainProbability,
  }) : assert(hour >= 0 && hour <= 24 && hour % 3 == 0),
       assert(
         rainProbability == null ||
             (rainProbability >= 0 && rainProbability <= 100),
       );

  final int hour;
  final String summary;
  final IconData icon;
  final double? temperatureCelsius;
  final int? rainProbability;
}

/// A reusable card; it never invents a location or fetches weather itself.
class WeatherForecastCard extends StatelessWidget {
  const WeatherForecastCard({
    super.key,
    required this.locationLabel,
    this.hours = const [],
    this.currentSummary,
    this.currentTemperatureCelsius,
    this.rainApproachMessage,
    this.onOpenRadar,
    this.radarSupported = false,
    this.updatedAt,
    this.sourceLabel,
    this.loading = false,
    this.failed = false,
    this.onRefresh,
  });

  final String locationLabel;
  final List<WeatherForecastHour> hours;
  final String? currentSummary;
  final double? currentTemperatureCelsius;
  final String? rainApproachMessage;
  final VoidCallback? onOpenRadar;
  final bool radarSupported;
  final DateTime? updatedAt;
  final String? sourceLabel;
  final bool loading;
  final bool failed;
  final VoidCallback? onRefresh;

  static const helpText =
      '出勤前は登録済みの自宅周辺、出勤後は登録済みの現場周辺を表示します。自宅住所の登録前は会社周辺です。'
      '表示地域と更新日時を確認してください。選択日0〜24時の3時間ごとの天気・気温・降水確率を表示します。'
      '左右の矢印で今日・明日・明後日を切り替えられます。最高・最低気温は取得していないため表示しません。'
      '晴れはオレンジ色の太陽、雨は青色の傘で表示します。'
      '降水確率は表示時刻の予報です。時間の列は横にスクロールできます。未取得の値は「未取得」または「—」と表示します。'
      '取得に失敗した場合、表示済みの予報は更新日時とともに残ります。更新ボタンで再取得できます。';

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_outlined, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(SkoLanguageController.tr('天気予報'))),
                IconButton(
                  tooltip: SkoLanguageController.tr('天気予報のヘルプ'),
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(SkoLanguageController.tr('天気予報')),
                      content: SingleChildScrollView(
                        child: Text(SkoLanguageController.tr(helpText)),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(SkoLanguageController.tr('閉じる')),
                        ),
                      ],
                    ),
                  ),
                  icon: Icon(Icons.help_outline, color: colors.primary),
                ),
                IconButton(
                  tooltip: SkoLanguageController.tr('天気予報を更新'),
                  onPressed: loading ? null : onRefresh,
                  icon: Icon(Icons.refresh, color: colors.primary),
                ),
              ],
            ),
            Text(
              locationLabel.trim().isEmpty
                  ? SkoLanguageController.tr('地域未設定')
                  : locationLabel,
            ),
            Text(
              SkoLanguageController.tr('出勤前：自宅周辺 ／ 出勤後：現場周辺の天気を表示'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (currentSummary != null) Text(currentSummary!),
            if (currentTemperatureCelsius != null)
              Text(_temperature(currentTemperatureCelsius)),
            if (rainApproachMessage != null) Text(rainApproachMessage!),
            if (updatedAt != null)
              Text(
                SkoLanguageController.trParams('更新 {time}', {
                  'time': _timestamp(updatedAt!),
                }),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (loading) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
              Text(SkoLanguageController.tr('天気予報を取得中')),
            ],
            if (failed) Text(SkoLanguageController.tr('最新の天気予報を取得できませんでした。')),
            if (hours.isEmpty && !loading && !failed)
              Text(SkoLanguageController.tr('天気予報は未取得です。')),
            if (hours.isNotEmpty) ...[
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final hour in weatherForecastHours)
                      Container(
                        width: 120,
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerLow,
                          border: Border.all(color: colors.outlineVariant),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('$hour${SkoLanguageController.tr('時')}'),
                            const SizedBox(height: 6),
                            Icon(
                              _at(hour)?.icon ?? Icons.cloud_outlined,
                              color: weatherConditionIconColor(
                                _at(hour)?.icon ?? Icons.cloud_outlined,
                                colors,
                              ),
                            ),
                            Text(
                              _at(hour)?.summary.trim().isNotEmpty == true
                                  ? _at(hour)!.summary
                                  : SkoLanguageController.tr('未取得'),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Text(_temperature(_at(hour)?.temperatureCelsius)),
                            Text(
                              SkoLanguageController.trParams('降水 {value}', {
                                'value': _at(hour)?.rainProbability == null
                                    ? SkoLanguageController.tr('未取得')
                                    : '${_at(hour)!.rainProbability}%',
                              }),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (radarSupported && onOpenRadar != null)
              TextButton.icon(
                onPressed: onOpenRadar,
                icon: Icon(Icons.radar, color: colors.primary),
                label: Text(SkoLanguageController.tr('雨雲レーダー')),
              ),
            if (sourceLabel != null && sourceLabel!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                SkoLanguageController.trParams('情報元：{source}', {
                  'source': sourceLabel!,
                }),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _temperature(double? value) => value == null || !value.isFinite
      ? SkoLanguageController.tr('未取得')
      : '${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1)}℃';
  WeatherForecastHour? _at(int hour) {
    for (final value in hours) {
      if (value.hour == hour) return value;
    }
    return null;
  }

  static String _timestamp(DateTime value) =>
      '${value.month}/${value.day} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}
