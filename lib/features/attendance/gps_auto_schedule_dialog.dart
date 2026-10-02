import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

class GpsAutoScheduleDraft {
  const GpsAutoScheduleDraft({
    required this.weekdays,
    required this.time,
  });

  final List<int> weekdays;
  final TimeOfDay time;

  String get dbTime =>
      time.hour.toString().padLeft(2, '0') +
      ':' +
      time.minute.toString().padLeft(2, '0') +
      ':00';

  String get label {
    const labels = <int, String>{
      1: '月',
      2: '火',
      3: '水',
      4: '木',
      5: '金',
      6: '土',
      7: '日',
    };
    final days = weekdays.map((day) => labels[day] ?? '').join('・');
    return days +
        ' / ' +
        time.hour.toString().padLeft(2, '0') +
        ':' +
        time.minute.toString().padLeft(2, '0');
  }
}

Future<bool> ensureGpsAutoLocationPermission(BuildContext context) async {
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.always) return true;
  if (!context.mounted) return false;

  final openSettings = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('GPS自動出勤には「常に許可」が必要です'),
      content: const Text(
        '指定時刻の前後にアプリが画面に出ていない状態でも現在地を確認するため、'
        'iPhoneの位置情報を「常に」に設定してください。'
        'GPS自動出勤を使わない時はバックグラウンド位置取得を行いません。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('あとで'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('iPhone設定を開く'),
        ),
      ],
    ),
  );
  if (openSettings == true) {
    await Geolocator.openAppSettings();
  }
  return false;
}

Future<GpsAutoScheduleDraft?> showGpsAutoScheduleDialog(
  BuildContext context, {
  List<int> initialWeekdays = const [1, 2, 3, 4, 5],
  TimeOfDay initialTime = const TimeOfDay(hour: 8, minute: 0),
}) async {
  var weekdays = <int>{...initialWeekdays};
  var time = initialTime;

  return showDialog<GpsAutoScheduleDraft>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('GPS自動出勤の曜日と取得時間'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '選択した曜日の指定時刻前後に位置情報を確認し、'
                '選択中の現場付近にいる場合だけ自動で出勤を記録します。',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final entry in const [
                    (1, '月'),
                    (2, '火'),
                    (3, '水'),
                    (4, '木'),
                    (5, '金'),
                    (6, '土'),
                    (7, '日'),
                  ])
                    FilterChip(
                      label: Text(entry.$2),
                      selected: weekdays.contains(entry.$1),
                      onSelected: (selected) {
                        setDialogState(() {
                          if (selected) {
                            weekdays.add(entry.$1);
                          } else {
                            weekdays.remove(entry.$1);
                          }
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule_outlined),
                title: const Text('GPS取得時間'),
                subtitle: Text(
                  time.hour.toString().padLeft(2, '0') +
                      ':' +
                      time.minute.toString().padLeft(2, '0'),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final selected = await showTimePicker(
                    context: context,
                    initialTime: time,
                  );
                  if (selected != null) {
                    setDialogState(() => time = selected);
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: weekdays.isEmpty
                ? null
                : () => Navigator.pop(
                      dialogContext,
                      GpsAutoScheduleDraft(
                        weekdays: weekdays.toList()..sort(),
                        time: time,
                      ),
                    ),
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
}

TimeOfDay gpsTimeFromDatabase(Object? value) {
  final text = value?.toString() ?? '';
  final parts = text.split(':');
  if (parts.length < 2) return const TimeOfDay(hour: 8, minute: 0);
  return TimeOfDay(
    hour: int.tryParse(parts[0]) ?? 8,
    minute: int.tryParse(parts[1]) ?? 0,
  );
}
