import 'package:flutter/material.dart';

import 'paid_work_hours_input_card.dart';
import 'paid_work_hours_repository.dart';

/// Ordinary report fields are still saved by the existing report repository.
/// The independent hours API writes only its explicit source-bound draft.
class PaidWorkHoursReportSection extends StatefulWidget {
  const PaidWorkHoursReportSection({super.key, required this.repository,
    required this.companyId, required this.reportId, required this.workerNames,
    required this.sourceRevision, required this.onSaved});
  final PaidWorkHoursRepository repository;
  final String companyId, reportId;
  final Map<String, String> workerNames;
  final Object? sourceRevision;
  final VoidCallback onSaved;

  @override
  State<PaidWorkHoursReportSection> createState() => _PaidWorkHoursReportSectionState();
}

class _PaidWorkHoursReportSectionState extends State<PaidWorkHoursReportSection> {
  late Future<List<PaidWorkHoursSnapshot>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<PaidWorkHoursSnapshot>> _load() => Future.wait([
    for (final worker in widget.workerNames.keys) widget.repository.load(
      companyId: widget.companyId, workerId: worker, reportId: widget.reportId),
  ]);

  @override
  void didUpdateWidget(covariant PaidWorkHoursReportSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.companyId != widget.companyId || oldWidget.reportId != widget.reportId ||
        oldWidget.workerNames.keys.join(',') != widget.workerNames.keys.join(',') ||
        !identical(oldWidget.sourceRevision, widget.sourceRevision)) _future = _load();
  }

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) => FutureBuilder<List<PaidWorkHoursSnapshot>>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator());
      }
      if (snapshot.hasError || snapshot.data == null) {
        return Card(child: ListTile(
          title: const Text('実勤務時間の設定状況を確認できません。'),
          subtitle: const Text('0時間として保存せず、再読込してください。'),
          trailing: TextButton(onPressed: _reload, child: const Text('再読込')),
        ));
      }
      return Column(children: [
        for (final state in snapshot.data!.where((r) => r.hoursRequired))
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.workerNames[state.workerId] ?? '社員'),
            PaidWorkHoursInputCard(
              key: ValueKey('${state.reportId}:${state.workerId}'),
              snapshot: state,
              onSave: (text) => widget.repository.save(state, text),
              onSaved: (_) { _reload(); widget.onSaved(); },
              onReload: _reload,
            ),
          ]),
      ]);
    },
  );
}

/// Run after the ordinary report draft and exact clock links have saved, and
/// before opening either existing signature UI. Earlier site reports can sign;
/// the final closed day report must carry an explicitly saved daily quantity.
String? paidWorkHoursSignatureProblem(Iterable<PaidWorkHoursSnapshot> values) {
  for (final state in values) {
    if (!state.hoursRequired) continue;
    if (state.sourceBlocked) {
      const intermediateReasons = {
        'report_is_not_final_closed_shift', 'open_shift', 'final_shift_missing',
      };
      if (state.sourceReasons.isNotEmpty && state.sourceReasons.every(intermediateReasons.contains)) continue;
      return '時間手当の勤務記録を確認できません。実勤務時間を再読込してください。';
    }
    if (!state.inputScopeCurrent || state.hours == null) {
      return '時間手当の実勤務時間を入力して保存してから、サインしてください。';
    }
  }
  return null;
}
