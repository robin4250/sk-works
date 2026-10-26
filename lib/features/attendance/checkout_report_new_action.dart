import 'package:flutter/material.dart';

import 'checkout_report_gate_repository.dart';
import 'checkout_report_resume_action.dart';
import 'checkout_report_resume_repository.dart';

/// Called only after the general report list's explicit '+' action. Browsing
/// that list or an existing report never invokes this function or saves intent.
/// True includes user cancellation and unavailable source: neither may fall
/// through to a legacy editor while the new source-bound flow is enforced.
Future<bool> offerNewCheckoutReport(BuildContext context, {
  required DateTime month,
  String? workerId,
  CheckoutReportGateRepository? gateRepository,
  CheckoutReportResumeRepository? resumeRepository,
  CheckoutReportOpener? opener,
}) async {
  final gate = gateRepository ?? CheckoutReportGateRepository.maybeCreate();
  if (gate == null) return false;
  final actor = gate.actorId;
  await gate.readPending();
  if (!context.mounted) return true;
  if (actor == null || gate.actorId != actor) throw StateError('ログイン状態が変わりました。');
  if (gate.choiceEnforcementEnabled == false) return false;
  if (gate.choiceEnforcementEnabled != true) throw StateError('日報作成の提供状態を確認できません。');
  // Another worker's administrative editor retains its existing authority path.
  if (workerId != null && !await gate.isOwnWorker(workerId)) return false;
  if (!context.mounted) return true;
  final rows = await gate.readCreationSources(month);
  if (gate.actorId != actor) throw StateError('ログイン状態が変わりました。');
  if (!context.mounted) return true;
  final pending = rows.where((row) => row.choiceAvailable &&
    row.workDate.year == month.year && row.workDate.month == month.month &&
    (workerId == null || row.workerId == workerId)).toList();
  if (pending.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('この月に作成・再開できる本人の退勤記録がありません。出勤表で勤務日を確認してください。')));
    }
    return true;
  }
  final resume = resumeRepository ?? CheckoutReportResumeRepository.maybeCreate();
  if (resume == null) throw StateError('勤務原本を確認できません。');
  final days = <String, List<CheckoutReportResumeTarget>>{};
  final targets = <CheckoutReportResumeTarget>[];
  for (final row in pending) {
    final key = '${row.workerId}/${row.workDate}';
    final saved = days[key] ??= await resume.loadDay(workerId: row.workerId, workDate: row.workDate);
    if (gate.actorId != actor) throw StateError('ログイン状態が変わりました。');
    final matches = saved.where((target) => target.sourceClockInId == row.sourceClockInId && target.clockOutId == row.clockOutId &&
      target.companyId == row.companyId && target.workerId == row.workerId &&
      target.workDate == row.workDate && (target.needsCompletion || target.complete));
    for (final target in matches) {
      if (!targets.any((existing) => existing.sourceClockInId == target.sourceClockInId)) targets.add(target);
    }
  }
  if (!context.mounted) return true;
  if (targets.isEmpty) throw StateError('対象勤務の日報を作成できません。出勤表または勤怠管理で原本を確認してください。');
  final selected = await showModalBottomSheet<CheckoutReportResumeTarget>(
    context: context, isScrollControlled: true,
    builder: (sheet) => SafeArea(child: SingleChildScrollView(child: Column(
      mainAxisSize: MainAxisSize.min, children: [
        const ListTile(title: Text('作成・再開する勤務を選択')),
        for (final target in targets) ListTile(
          key: ValueKey('new-report-source-${target.sourceClockInId}'),
          title: Text('${target.workDate.month}/${target.workDate.day} ${target.destinationName}'),
          subtitle: Text(checkoutReportStateLabel(target)),
          trailing: const Icon(Icons.description_outlined),
          onTap: () => Navigator.pop(sheet, target)),
        TextButton(onPressed: () => Navigator.pop(sheet), child: const Text('戻る')),
      ]))));
  if (selected == null || !context.mounted) return true;
  if (gate.actorId != actor) throw StateError('ログイン状態が変わりました。');
  await openCheckoutReportResumeTarget(context, target: selected, repository: resume,
    gateRepository: gate, opener: opener);
  return true;
}
