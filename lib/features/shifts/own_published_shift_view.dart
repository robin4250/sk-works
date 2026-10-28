import 'package:flutter/material.dart';

import 'own_published_shift_gateway.dart';

/// Displays only server-published plans; these are not attendance records.
class OwnPublishedShiftView extends StatefulWidget {
  const OwnPublishedShiftView({super.key, required this.gateway,
    required this.companyId, required this.month, required this.siteNames});

  final OwnPublishedShiftGateway gateway;
  final String companyId;
  final DateTime month;
  final Map<String, String> siteNames;

  @override
  State<OwnPublishedShiftView> createState() => _OwnPublishedShiftViewState();
}

class _OwnPublishedShiftViewState extends State<OwnPublishedShiftView> {
  late Future<List<OwnPublishedShift>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant OwnPublishedShiftView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gateway != widget.gateway ||
        oldWidget.companyId != widget.companyId ||
        oldWidget.month.year != widget.month.year ||
        oldWidget.month.month != widget.month.month) {
      _reload();
    }
  }

  void _reload() {
    _future = widget.gateway.listMonth(widget.companyId, widget.month);
  }

  String _time(int minute) => '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => FutureBuilder<List<OwnPublishedShift>>(
    key: ObjectKey(_future),
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('シフトを確認できません。もう一度開いてください。'),
        TextButton(onPressed: () => setState(_reload), child: const Text('再読み込み')),
      ]);
      }
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final shifts = snapshot.data!;
      if (shifts.isEmpty) return const Text('公開されたシフトはありません。');
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('確定シフト（予定）'),
        for (final shift in shifts)
          Card(child: ListTile(
            title: Text('${shift.day.month}月${shift.day.day}日　${shift.holiday ? '休日' : shift.night ? '夜勤' : '日勤'}'),
            subtitle: Text(shift.holiday ? '休日' : '${shift.siteId == null ? '現場未設定' : widget.siteNames[shift.siteId] ?? '現場を確認できません'}\n${_time(shift.startMinute)} 〜 ${_time(shift.endMinute)}${shift.endMinute <= shift.startMinute ? '（翌日）' : ''}'),
          )),
      ]);
    },
  );
}
