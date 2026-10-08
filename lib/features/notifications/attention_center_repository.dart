import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import 'app_notification_repository.dart';
import 'attention_center_item.dart';
import 'notification_business_status.dart';

class AttentionCenterData {
  const AttentionCenterData({
    required this.snapshot,
    required this.notificationsById,
    required this.notificationIdsByItemKey,
    required this.unavailableSources,
  });

  final AttentionCenterSnapshot snapshot;
  final Map<String, AppNotificationRecord> notificationsById;
  final Map<String, List<String>> notificationIdsByItemKey;
  final Set<String> unavailableSources;
}

class AttentionCenterRepository {
  AttentionCenterRepository._(this._client, this._notifications);
  final SupabaseClient _client;
  final AppNotificationRepository _notifications;

  static AttentionCenterRepository? maybeCreate() {
    final notifications = AppNotificationRepository.maybeCreate();
    if (notifications == null) return null;
    return AttentionCenterRepository._(SupabaseBackend.client, notifications);
  }

  Future<AttentionCenterData> load({Set<String>? availableActionKeys}) async {
    final failures = <String>{};
    var notifications = const <AppNotificationRecord>[];
    final items = <AttentionCenterItem>[];
    Future<void> readSource(String source, Future<void> Function() read) async {
      try {
        await read();
      } catch (_) {
        failures.add(source);
      }
    }
    await Future.wait([
      readSource('notifications', () async {
        notifications = await _notifications.load();
        items.addAll(notifications.map((item) => mapAttentionNotification(item,
            availableActionKeys: availableActionKeys)));
      }),
      readSource('required_documents', () async {
        items.addAll(mapRequiredDocumentAttention(
          await _client.rpc('current_user_required_document_attention'),
          availableActionKeys: availableActionKeys,
        ));
      }),
      readSource('paid_leave', () async {
        items.addAll(mapPaidLeaveAttention(
          await _client.rpc('pending_paid_leave_request_batches'),
          availableActionKeys: availableActionKeys,
        ));
      }),
      readSource('generation_settings', () async {
        items.addAll(mapGenerationAttention(
          await _client.rpc('current_generation_setting_attention'),
          availableActionKeys: availableActionKeys,
        ));
      }),
    ]);
    final idsByKey = <String, List<String>>{};
    for (final item in notifications) {
      final key = mapAttentionNotification(item).deduplicationKey;
      idsByKey.putIfAbsent(key, () => []).add(item.id);
    }
    return AttentionCenterData(
      snapshot: AttentionCenterSnapshot(items, now: DateTime.now()),
      notificationsById: Map.unmodifiable({for (final item in notifications) item.id: item}),
      notificationIdsByItemKey: Map.unmodifiable({
        for (final entry in idsByKey.entries) entry.key: List<String>.unmodifiable(entry.value),
      }),
      unavailableSources: Set.unmodifiable(failures),
    );
  }
}

bool _canOpen(String? action, Set<String>? available) =>
    action != null && action.isNotEmpty && (available == null || available.contains(action));
String? _text(Object? value) => value?.toString();
DateTime? _date(Object? value) => DateTime.tryParse(value?.toString() ?? '');

AttentionCenterItem mapAttentionNotification(AppNotificationRecord item,
    {Set<String>? availableActionKeys}) {
  final state = item.hasBusinessTarget
      ? switch (item.businessStatus.state) {
          NotificationBusinessState.pending => AttentionCenterState.pending,
          NotificationBusinessState.completed => AttentionCenterState.completed,
          NotificationBusinessState.rejected => AttentionCenterState.rejected,
          NotificationBusinessState.cancelled => AttentionCenterState.cancelled,
          NotificationBusinessState.unknown => AttentionCenterState.unknown,
        }
      : AttentionCenterState.information;
  return AttentionCenterItem(
    id: item.id, source: 'notification', title: item.title, body: item.body,
    state: state, actionKey: item.actionKey, actionId: item.actionId,
    targetName: item.businessStatus.targetName,
    targetDate: item.businessStatus.targetDate, createdAt: item.createdAt,
    read: item.read, actionable: _canOpen(item.actionKey, availableActionKeys),
    evidenceRank: state == AttentionCenterState.unknown ? 0 : 20,
  );
}

List<AttentionCenterItem> mapRequiredDocumentAttention(Object? raw,
    {Set<String>? availableActionKeys}) {
  if (raw is! Map || raw['missing_names'] is! List) return const [];
  return [for (final name in raw['missing_names'] as List)
    if (name is String && name.trim().isNotEmpty)
      AttentionCenterItem(
        id: name, source: 'required_document', title: name,
        state: AttentionCenterState.pending, actionKey: 'document_register',
        metadata: {'document_name': name}, evidenceRank: 10,
        actionable: _canOpen('document_register', availableActionKeys),
      ),
  ];
}

List<AttentionCenterItem> mapPaidLeaveAttention(Object? raw,
    {Set<String>? availableActionKeys}) {
  if (raw is! List) return const [];
  return [for (final row in raw)
    if (row is Map && (_text(row['batch_id'])?.isNotEmpty ?? false))
      AttentionCenterItem(
        id: row['batch_id'].toString(), source: 'paid_leave',
        title: '有給申請', body: _text(row['reason']) ?? '',
        state: AttentionCenterState.pending, actionKey: 'paid_leave_request',
        actionId: row['batch_id'].toString(), targetName: _text(row['requested_by_name']),
        targetDate: _date(row['first_date']), createdAt: _date(row['submitted_at']),
        metadata: {'first_date': row['first_date'], 'last_date': row['last_date'],
          'date_count': row['date_count'], 'requested_by': row['requested_by']},
        evidenceRank: 10, actionable: _canOpen('paid_leave_request', availableActionKeys),
      ),
  ];
}

List<AttentionCenterItem> mapGenerationAttention(Object? raw,
    {Set<String>? availableActionKeys}) {
  if (raw is! Map || raw['issues'] is! List) return const [];
  return [for (final row in raw['issues'] as List)
    if (row is Map && (_text(row['type'])?.isNotEmpty ?? false) &&
        (_text(row['key'])?.isNotEmpty ?? false))
      AttentionCenterItem(
        id: '${row['type'].toString().length}:${row['type']}:${row['key']}',
        source: 'generation_setting', title: _text(row['message']) ?? '',
        state: AttentionCenterState.pending,
        actionKey: _text(row['action_key']), actionId: _text(row['action_id']),
        metadata: {'type': row['type'], 'key': row['key'], 'message': row['message'],
          'action_key': row['action_key'], 'action_id': row['action_id']},
        deadline: _date(row['deadline']), evidenceRank: 10,
        actionable: _canOpen(_text(row['action_key']), availableActionKeys),
      ),
  ];
}
