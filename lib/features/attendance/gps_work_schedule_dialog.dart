import 'package:flutter/material.dart';

class GpsWorkScheduleDraft {
  const GpsWorkScheduleDraft({required this.weekdays, required this.clockIn,
    required this.checkoutReminder});
  final List<int> weekdays;
  final TimeOfDay clockIn, checkoutReminder;
  String _db(TimeOfDay v) => '${v.hour.toString().padLeft(2, '0')}:${v.minute.toString().padLeft(2, '0')}:00';
  String get clockInDatabase => _db(clockIn);
  String get checkoutDatabase => _db(checkoutReminder);
  String get label {
    const days = {1:'月',2:'火',3:'水',4:'木',5:'金',6:'土',7:'日'};
    return '${weekdays.map((v) => days[v] ?? '').join('・')} / 出勤 ${clockInDatabase.substring(0,5)} / 退勤確認 ${checkoutDatabase.substring(0,5)}${checkoutNextDay ? '（翌日）' : ''}';
  }
  bool get checkoutNextDay => checkoutReminder.hour * 60 + checkoutReminder.minute < clockIn.hour * 60 + clockIn.minute;
}

Future<GpsWorkScheduleDraft?> showGpsWorkScheduleDialog(BuildContext context, {
  List<int> initialWeekdays = const [1, 2, 3, 4, 5],
  TimeOfDay initialClockIn = const TimeOfDay(hour: 8, minute: 0),
  TimeOfDay initialCheckoutReminder = const TimeOfDay(hour: 17, minute: 0),
}) => showDialog<GpsWorkScheduleDraft>(context: context, builder: (context) =>
    GpsWorkScheduleDialog(initialWeekdays: initialWeekdays,
      initialClockIn: initialClockIn, initialCheckoutReminder: initialCheckoutReminder));

class GpsWorkScheduleDialog extends StatefulWidget {
  const GpsWorkScheduleDialog({super.key, this.initialWeekdays = const [1, 2, 3, 4, 5],
    this.initialClockIn = const TimeOfDay(hour: 8, minute: 0),
    this.initialCheckoutReminder = const TimeOfDay(hour: 17, minute: 0)});
  final List<int> initialWeekdays;
  final TimeOfDay initialClockIn, initialCheckoutReminder;
  @override State<GpsWorkScheduleDialog> createState() => _GpsWorkScheduleDialogState();
}
class _GpsWorkScheduleDialogState extends State<GpsWorkScheduleDialog> {
  late final Set<int> _days = {...widget.initialWeekdays};
  late TimeOfDay _in = widget.initialClockIn, _out = widget.initialCheckoutReminder;
  String _label(TimeOfDay v) => '${v.hour.toString().padLeft(2, '0')}:${v.minute.toString().padLeft(2, '0')}';
  int _minutes(TimeOfDay v) => v.hour * 60 + v.minute;
  Future<void> _pick(bool clockIn) async {
    final value = await showTimePicker(context: context, initialTime: clockIn ? _in : _out);
    if (value != null && mounted) { setState(() { if (clockIn) { _in = value; } else { _out = value; } }); }
  }
  @override Widget build(BuildContext context) {
    final same = _minutes(_in) == _minutes(_out);
    return AlertDialog(title: const Text('GPS出勤・退勤の確認'),
      content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('曜日と出勤・退勤確認の時刻を設定します。現場は前の画面で選択した場所を使います。'),
          const SizedBox(height: 12),
          Wrap(spacing: 4, runSpacing: 4, children: [for (final d in const [(1,'月'),(2,'火'),(3,'水'),(4,'木'),(5,'金'),(6,'土'),(7,'日')])
            FilterChip(label: Text(d.$2), selected: _days.contains(d.$1), onSelected: (v) => setState(() { if (v) { _days.add(d.$1); } else { _days.remove(d.$1); } }))]),
          ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.login),
            title: const Text('出勤時刻'), subtitle: Text(_label(_in)), onTap: () => _pick(true)),
          ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('退勤確認時刻'), subtitle: Text('${_label(_out)}${_minutes(_out) < _minutes(_in) ? '（翌日）' : ''}'), onTap: () => _pick(false)),
          if (same) const Text('出勤時刻と退勤確認時刻を別の時刻にしてください。', style: TextStyle(color: Colors.red)),
          const ExpansionTile(tilePadding: EdgeInsets.zero, leading: Icon(Icons.help_outline),
            title: Text('使い方'), children: [Padding(padding: EdgeInsets.only(bottom: 12), child: Text(
              '出勤時刻の前後に現場付近へいることを確認して出勤を記録します。退勤確認時刻には通知し、本人が退勤を確定して日報・報告者サインへ進みます。まだ勤務中なら30分後に再通知できます。時刻だけで自動退勤やサイン保存は行いません。通知の表示にはiPhoneの許可が必要です。'))]),
        ],
      ))), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('戻る')),
        FilledButton(onPressed: _days.isEmpty || same ? null : () => Navigator.pop(context,
          GpsWorkScheduleDraft(weekdays: _days.toList()..sort(), clockIn: _in, checkoutReminder: _out)), child: const Text('保存'))]);
  }
}
