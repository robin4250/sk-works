import 'package:flutter/material.dart';

import '../../international/language_controller.dart';
import '../daily_reports/daily_report_page.dart';
import 'checkout_report_resume_repository.dart';

typedef CheckoutReportOpener = Future<void> Function(
    BuildContext context, CheckoutReportResumeTarget target);

String checkoutReportStateLabel(CheckoutReportResumeTarget target) => switch (target.state) {
  CheckoutReportState.missing => '退勤済み・日報未作成',
  CheckoutReportState.draft => '日報の報告者サインが未登録です',
  CheckoutReportState.partialSignature => target.reporterSignatureSaved
      ? '現場責任者のサイン待ち' : '日報の報告者サインが未登録です',
  CheckoutReportState.complete => '日報確定済み',
  CheckoutReportState.signedWithoutAttendance => '日報から勤怠への反映確認が必要です',
  CheckoutReportState.protectedPeriod => '確定済み給与の対象です。管理者が確認してください',
  CheckoutReportState.conflict => '勤務原本の確認が必要です。管理者が確認してください',
};

Future<CheckoutReportResumeTarget> openCheckoutReportResumeTarget(
  BuildContext context, {
  required CheckoutReportResumeTarget target,
  required CheckoutReportResumeRepository repository,
  CheckoutReportOpener? opener,
}) async {
  final current = await repository.revalidate(target);
  if (!context.mounted) { return current; }
  if (!current.needsCompletion && !current.complete) {
    throw StateError(checkoutReportStateLabel(current));
  }
  if (opener != null) {
    await opener(context, current);
  } else {
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => DailyReportPage(
        initialDate: current.workDate, initialSiteId: current.siteId,
        initialRouteAssignmentId: current.routeId, initialReportId: current.reportId,
        vehicleClockInId: current.sourceClockInId,
        groupClockInAnchorId: current.sourceClockInId,
      ),
    ));
  }
  return repository.revalidate(current);
}

/// Returns true when this day had a saved-checkout continuation to handle.
/// A false result keeps the caller's existing saved-report calendar behavior.
Future<bool> offerCheckoutReportResumeForDay(
  BuildContext context, {
  required String workerId, required DateTime workDate,
  CheckoutReportResumeRepository? repository,
  CheckoutReportOpener? opener,
}) async {
  final reader = repository ?? CheckoutReportResumeRepository.maybeCreate();
  if (reader == null) { throw StateError('日報の作成状況を確認できません。接続を確認してください。'); }
  final targets = await reader.loadDay(workerId: workerId, workDate: workDate);
  if (!context.mounted) { return true; }
  if (targets.isEmpty || targets.every((target) => target.complete)) { return false; }
  final selected = await showModalBottomSheet<CheckoutReportResumeTarget>(
    context: context, isScrollControlled: true,
    builder: (sheet) => SafeArea(child: SingleChildScrollView(child: Column(
      mainAxisSize: MainAxisSize.min, children: [
        ListTile(title: Text(SkoLanguageController.tr('退勤後の日報を作成・再開')),
          subtitle: Text('${workDate.year}/${workDate.month}/${workDate.day}')),
        for (final target in targets)
          ListTile(key: ValueKey('resume-checkout-report-${target.sourceClockInId}'),
            title: Text(target.destinationName),
            subtitle: Text(SkoLanguageController.tr(checkoutReportStateLabel(target))),
            trailing: const Icon(Icons.description_outlined),
            onTap: target.needsCompletion || target.complete
                ? () => Navigator.pop(sheet, target) : null),
      ],
    ))),
  );
  if (selected == null || !context.mounted) { return true; }
  final after = await openCheckoutReportResumeTarget(context,
    target: selected, repository: reader, opener: opener);
  if (!context.mounted) { return true; }
  final message = after.complete
      ? '日報の確定と正式勤怠への反映を確認しました。'
      : after.reporterSignatureSaved && !after.responsibleSignatureSaved
          ? '現場責任者のサインがないため、給与に未反映です。'
          : '退勤は記録済みです。日報の登録・報告者サインを完了してください。';
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(SkoLanguageController.tr(message))));
  return true;
}

void showCheckoutReportResumeHelp(BuildContext context) => showDialog<void>(
  context: context,
  builder: (dialog) => AlertDialog(
    title: Text(SkoLanguageController.tr('退勤後の日報')),
    content: Text(SkoLanguageController.tr(
      '出勤表の日付を押すと、保存済みの退勤から日報を作成・再開できます。もう一度出勤・退勤する必要はありません。報告者サインを保存し、現場責任者のサインは後から取得できます。給与・請求への反映には正規の日報確定が必要です。確定済み日報や給与をこの操作で書き換えません。')),
    actions: [TextButton(onPressed: () => Navigator.pop(dialog),
      child: Text(SkoLanguageController.tr('閉じる')))],
  ),
);
