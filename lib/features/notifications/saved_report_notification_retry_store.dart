import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Only saved identifiers are stored, never report bodies or recipient data.
class SavedReportNotificationRetry {
  const SavedReportNotificationRetry({required this.userId, required this.companyId, required this.reportId});
  final String userId;
  final String companyId;
  final String reportId;

  Map<String, String> toJson() => {'company_id': companyId, 'report_id': reportId};
}

class SavedReportNotificationRetryStore {
  SavedReportNotificationRetryStore({Future<String?> Function(String)? read,
    Future<void> Function(String, String)? write})
      : _readString = read ?? SharedPreferencesAsync().getString,
        _writeString = write ?? SharedPreferencesAsync().setString;

  final Future<String?> Function(String) _readString;
  final Future<void> Function(String, String) _writeString;
  static Future<void> _writes = Future<void>.value();

  String _key(String userId) => 'sko.saved_report_notification_retry.v1.$userId';

  Future<List<SavedReportNotificationRetry>> load(String userId) async {
    await _writes;
    return _read(userId);
  }

  Future<List<SavedReportNotificationRetry>> _read(String userId) async {
    final raw = await _readString(_key(userId));
    if (raw == null) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) throw const FormatException('Invalid saved notification retry list');
    return decoded.map((value) {
      if (value is! Map || value['company_id'] is! String || value['report_id'] is! String ||
          (value['company_id'] as String).isEmpty || (value['report_id'] as String).isEmpty) {
        throw const FormatException('Invalid saved notification retry identifier');
      }
      return SavedReportNotificationRetry(userId: userId,
        companyId: value['company_id'] as String, reportId: value['report_id'] as String);
    }).toList();
  }

  Future<void> remember(SavedReportNotificationRetry retry) => _change(retry, remove: false);
  Future<void> confirmed(SavedReportNotificationRetry retry) => _change(retry, remove: true);

  Future<void> _change(SavedReportNotificationRetry retry, {required bool remove}) {
    final operation = _writes.then((_) async {
      final entries = await _read(retry.userId);
      entries.removeWhere((entry) => entry.companyId == retry.companyId && entry.reportId == retry.reportId);
      if (!remove) entries.add(retry);
      await _writeString(_key(retry.userId), jsonEncode(entries.map((entry) => entry.toJson()).toList()));
    });
    // A failed write must not poison later retries or erase previous data.
    _writes = operation.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return operation;
  }
}

/// Persist before issuing RPC. A crash, denial, missing RPC or zero result keeps
/// the exact saved ID. Only a positive, confirmed publication removes it.
Future<bool> retryPersistedSavedReportNotification(SavedReportNotificationRetry retry, {
  required Future<void> Function(SavedReportNotificationRetry) remember,
  required Future<void> Function(SavedReportNotificationRetry) verifySaved,
  required Future<bool> Function(String) publish,
  required Future<void> Function(SavedReportNotificationRetry) confirmed,
}) async {
  await remember(retry);
  await verifySaved(retry);
  final sent = await publish(retry.reportId);
  if (sent) await confirmed(retry);
  return sent;
}

/// Derive scope only from the actual saved report row, never the selected site
/// or first company membership. Publication still rechecks server access.
SavedReportNotificationRetry? savedReportNotificationScopeFromRow(
  Map<String, dynamic> row, String? userId,
) {
  final id = row['id'];
  final companyId = row['company_id'];
  if (userId == null || row['updated_by'] != userId ||
      id is! String || id.isEmpty || companyId is! String || companyId.isEmpty) {
    return null;
  }
  return SavedReportNotificationRetry(
    userId: userId, companyId: companyId, reportId: id,
  );
}
