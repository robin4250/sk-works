import 'package:flutter/material.dart';
import 'daily_report_month_repository.dart';

/// Uses persisted save state; two signatures alone never mean finalized.
class DailyReportSaveBadge extends StatelessWidget {
  const DailyReportSaveBadge({super.key, required this.state, this.count});
  final DailyReportSaveState state;
  final int? count;
  @override
  Widget build(BuildContext context) {
    final complete = state == DailyReportSaveState.saved;
    final pending = state == DailyReportSaveState.supervisorPending;
    final color = complete ? Colors.green.shade800 : pending ? Colors.red.shade900
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final foreground = color;
    final icon = complete ? Icons.check_circle_outline : pending ? Icons.pending_actions
        : Icons.edit_note;
    return Container(
      key: ValueKey('daily-report-save-badge-${state.name}'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, border: Border.all(color: color),
        borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 18, color: foreground),
        const SizedBox(width: 4),
        Text('${state.label}${count == null ? '' : ' $count件'}',
          style: TextStyle(color: foreground, fontWeight: FontWeight.bold)),
      ]),
    );
  }
}
