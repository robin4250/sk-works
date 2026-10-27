import 'package:flutter/material.dart';

import 'own_published_shift_gateway.dart';

/// Displays only server-published plans; these are not attendance records.
class OwnPublishedShiftView extends StatelessWidget {
  const OwnPublishedShiftView({super.key, required this.gateway,
    required this.companyId, required this.month, required this.siteNames});

  final OwnPublishedShiftGateway gateway;
  final String companyId;
  final DateTime month;
  final Map<String, String> siteNames;

  String _time(int minute) => '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => FutureBuilder<List<OwnPublishedShift>>(
    future: gateway.listMonth(companyId, month),
    builder: (context, snapshot) {
      if (snapshot.hasError) return const Text('シフトを確認できません。もう一度開いてください。');
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final shifts = snapshot.data!;
      if (shifts.isEmpty) return const Text('公開されたシフトはありません。');
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('確定シフト（予定）'),
        for (final shift in shifts)
          Card(child: ListTile(
            title: Text('${shift.day.month}月${shift.day.day}日　${shift.holiday ? '休日' : shift.night ? '夜勤' : '日勤'}'),
            subtitle: Text(shift.holiday ? '休日' : '${shift.siteId == null ? '現場未設定' : siteNames[shift.siteId] ?? '現場を確認できません'}\n${_time(shift.startMinute)} 〜 ${_time(shift.endMinute)}${shift.endMinute <= shift.startMinute ? '（翌日）' : ''}'),
          )),
      ]);
    },
  );
}
