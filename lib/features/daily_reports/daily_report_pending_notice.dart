import 'package:flutter/material.dart';
import '../../international/language_controller.dart';

/// Report completion is separate from a saved clock event or a payroll amount.
class DailyReportPendingNotice extends StatelessWidget {
  const DailyReportPendingNotice({
    super.key,
    required this.hasClockedInWorkers,
    required this.isSigned,
  });

  final bool hasClockedInWorkers;
  final bool isSigned;

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    if (!hasClockedInWorkers || isSigned) return const SizedBox.shrink();
    return Card(
      child: ListTile(
        leading: Icon(Icons.pending_actions_outlined),
        title: Text(SkoLanguageController.tr('打刻済み・日報未確定')),
        subtitle: Text(
          SkoLanguageController.tr('打刻と日報の確定は別の状態です。内容を確認し、報告者・責任者のサインで日報を確定してください。'),
        ),
      ),
    );
  }
}
