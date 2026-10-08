import '../attendance/group_checkout_repository.dart';
import 'daily_report_repository.dart';

/// Retains saved report values; actual clock-in evidence adds missing draft members.
/// Signed reports never gain members before an approved edit.
List<DailyReportWorkerDraft> mergeAnchoredGroupRoster({
  required List<DailyReportWorkerDraft> existing,
  required List<DailyReportWorkerDraft> fallback,
  required List<GroupCheckoutCandidate> candidates,
  required bool allowNewMembers,
}) {
  final sourceByWorker = {for (final row in candidates) row.workerId: row};
  final existingIds = existing.map((worker) => worker.workerId).toSet();
  final fallbackByWorker = {for (final worker in fallback) worker.workerId: worker};
  DailyReportWorkerDraft copy(DailyReportWorkerDraft worker) => DailyReportWorkerDraft(
    workerId: worker.workerId, workerName: worker.workerName,
    overtimeHours: worker.overtimeHours, earlyHours: worker.earlyHours,
    nightHours: worker.nightHours, allowanceAmount: worker.allowanceAmount,
    allowanceLabel: worker.allowanceLabel, vehicleId: worker.vehicleId,
    vehicleName: worker.vehicleName, routeId: worker.routeId, routeName: worker.routeName,
    odometerKm: worker.odometerKm, meterManaged: worker.meterManaged,
    meterEventId: worker.meterEventId, meterSourceClockInId: worker.meterSourceClockInId,
    previousOdometerKm: worker.previousOdometerKm, tripDistanceKm: worker.tripDistanceKm,
    sourceClockInId: sourceByWorker[worker.workerId]?.sourceId,
    sourceClockOutAt: sourceByWorker[worker.workerId]?.clockOutAt,
  );
  return List.unmodifiable([
    for (final worker in existing) copy(worker),
    if (allowNewMembers)
      for (final candidate in candidates)
        if (!existingIds.contains(candidate.workerId))
          copy(fallbackByWorker[candidate.workerId] ?? DailyReportWorkerDraft(
            workerId: candidate.workerId, workerName: candidate.name)),
  ]);
}
