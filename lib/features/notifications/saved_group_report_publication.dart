import 'package:supabase_flutter/supabase_flutter.dart';

/// Invokes the source-bound server publisher with only the already saved ID.
/// False means the staged publisher is unavailable; it does not mean sent.
/// Zero is valid for OFF or a durable receipt that already prevented a repeat.
Future<bool> publishSavedGroupReport(String reportId, {
  required Future<dynamic> Function(String reportId) invoke,
}) async {
  if (reportId.isEmpty) throw ArgumentError.value(reportId, 'reportId');
  try {
    final count = await invoke(reportId);
    if (count is! int || count < 0) {
      throw StateError('日報通知の結果を確認できません');
    }
    return true;
  } on PostgrestException catch (error) {
    if (error.code == 'PGRST202' || error.code == '42883') return false;
    rethrow;
  }
}

/// Manual or still-working roster rows cannot meet the server source contract.
bool groupReportPublicationEligible({
  required String? anchorSourceId,
  required String? siteId,
  required String? routeAssignmentId,
  required Iterable<({String? sourceId, DateTime? clockOutAt})> roster,
}) {
  return anchorSourceId != null && siteId != null && routeAssignmentId == null &&
    roster.isNotEmpty && roster.every((row) => row.sourceId != null && row.clockOutAt != null);
}

/// Used only by explicit registration, never internal signature draft saves.
/// A failed/partial save cannot reach publication; the returned saved ID is fixed.
Future<String?> registerSavedGroupReport({
  required bool notificationEligible,
  required Future<String?> Function() save,
  required Future<void> Function(String reportId) publish,
}) async {
  final id = await save();
  if (id != null && notificationEligible) await publish(id);
  return id;
}
