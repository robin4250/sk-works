import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../data/supabase_backend.dart';
import '../notifications/app_notification_repository.dart';

String attendanceBadgeJstDate(DateTime instant) =>
    instant.toUtc().add(const Duration(hours: 9)).toIso8601String().substring(0, 10);

class AttendanceBadgeScope {
  const AttendanceBadgeScope(this.actorId, this.companyId, this.date);
  final String actorId;
  final String companyId;
  final String date;
  String get storageKey => 'attendance-update-seen-v1:${base64Url.encode(utf8.encode(jsonEncode([actorId, companyId, date])))}';
  bool same(AttendanceBadgeScope other) =>
      actorId == other.actorId && companyId == other.companyId && date == other.date;
}

class AttendanceBadgeSnapshot {
  AttendanceBadgeSnapshot(this.scope, Iterable<String> pendingSourceIds, this.capturedAt)
      : pendingSourceIds = Set.unmodifiable(pendingSourceIds);
  final AttendanceBadgeScope scope;
  final Set<String> pendingSourceIds;
  final DateTime capturedAt;
  int get count => pendingSourceIds.length;
}

/// The badge acknowledges this device's observed clock-in notification sources.
/// It never marks the inbox read and never changes attendance evidence.
class AttendanceUpdateBadgeRepository {
  AttendanceUpdateBadgeRepository({
    required this.currentActor,
    required this.loadUnread,
    required this.loadSources,
    required this.readSeen,
    required this.writeSeen,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  final String? Function() currentActor;
  final Future<List<AppNotificationRecord>> Function() loadUnread;
  final Future<List<Map<String, dynamic>>> Function(String company, List<String> ids) loadSources;
  final Future<List<String>> Function(String key) readSeen;
  final Future<bool> Function(String key, List<String> ids) writeSeen;
  final DateTime Function() now;

  static AttendanceUpdateBadgeRepository? maybeCreate() {
    final notifications = AppNotificationRepository.maybeCreate();
    if (notifications == null) return null;
    final client = SupabaseBackend.client;
    return AttendanceUpdateBadgeRepository(
      currentActor: () => client.auth.currentUser?.id,
      loadUnread: notifications.unreadTargets,
      loadSources: (company, ids) async {
        final result = <Map<String, dynamic>>[];
        for (var offset = 0; offset < ids.length; offset += 200) {
          final end = (offset + 200).clamp(0, ids.length);
          final rows = await client.from('attendance_verifications')
              .select('id,company_id,event_type,confirmed_at')
              .eq('company_id', company).inFilter('id', ids.sublist(offset, end));
          result.addAll(rows.map((row) => Map<String, dynamic>.from(row)));
        }
        return result;
      },
      readSeen: (key) async => (await SharedPreferences.getInstance()).getStringList(key) ?? [],
      writeSeen: (key, ids) async => (await SharedPreferences.getInstance()).setStringList(key, ids),
    );
  }

  void _verify(AttendanceBadgeScope scope) {
    if (scope.actorId.isEmpty || scope.companyId.isEmpty ||
        currentActor() != scope.actorId || attendanceBadgeJstDate(now()) != scope.date) {
      throw StateError('Attendance badge scope changed');
    }
  }

  Future<AttendanceBadgeSnapshot> load(AttendanceBadgeScope scope) async {
    _verify(scope);
    final notices = await loadUnread();
    _verify(scope);
    final uuid = RegExp(r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$');
    final ids = notices.where((notice) => !notice.read &&
        notice.kind == 'attendance' && notice.actionKey == 'attendance_today' &&
        uuid.hasMatch(notice.actionId ?? '')).map((notice) => notice.actionId!).toSet();
    final rows = ids.isEmpty ? <Map<String, dynamic>>[] : await loadSources(scope.companyId, ids.toList());
    _verify(scope);
    final seen = (await readSeen(scope.storageKey)).toSet();
    _verify(scope);
    final pending = <String>{};
    for (final row in rows) {
      final id = row['id']?.toString();
      final confirmed = DateTime.tryParse(row['confirmed_at']?.toString() ?? '');
      if (id != null && ids.contains(id) && !seen.contains(id) &&
          row['company_id'] == scope.companyId && row['event_type'] == 'clock_in' &&
          confirmed != null && attendanceBadgeJstDate(confirmed) == scope.date) {
        pending.add(id);
      }
    }
    return AttendanceBadgeSnapshot(scope, pending, now());
  }

  Future<void> acknowledge(AttendanceBadgeSnapshot snapshot, DateTime openedAt) async {
    _verify(snapshot.scope);
    if (snapshot.capturedAt.isAfter(openedAt)) {
      throw StateError('Only a pre-open snapshot may be acknowledged');
    }
    final old = await readSeen(snapshot.scope.storageKey);
    _verify(snapshot.scope);
    final ids = {...old, ...snapshot.pendingSourceIds}.toList()..sort();
    if (!await writeSeen(snapshot.scope.storageKey, ids)) {
      throw StateError('Attendance badge acknowledgement was not saved');
    }
    _verify(snapshot.scope);
  }
}
