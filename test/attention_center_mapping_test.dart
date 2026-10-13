import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/notifications/app_notification_repository.dart';
import 'package:sk_works/features/notifications/attention_center_item.dart';
import 'package:sk_works/features/notifications/attention_center_repository.dart';
import 'package:sk_works/features/notifications/notification_business_status.dart';

void main() {
  AppNotificationRecord notice(NotificationBusinessState state) => AppNotificationRecord(
    id: 'notice', kind: 'approval', title: '有給', body: '',
    createdAt: DateTime(2026, 10, 8), read: true, actionKey: 'paid_leave_request',
    actionId: 'batch-a', businessStatus: NotificationBusinessStatus(state: state));
  final leave = [{'batch_id': 'batch-a', 'requested_by_name': '社員A',
    'first_date': '2026-09-30', 'last_date': '2026-10-01', 'date_count': 2}];

  test('exact leave target deduplicates read message and current task', () {
    final snapshot = AttentionCenterSnapshot([
      mapAttentionNotification(notice(NotificationBusinessState.pending)),
      ...mapPaidLeaveAttention(leave),
    ], now: DateTime(2026, 10, 8));
    expect(snapshot.items.length, 1);
    expect(snapshot.unresolvedCount, 1);
    expect(snapshot.items.single.read, isTrue);
  });
  test('confirmed completion wins stale pending task evidence', () {
    final snapshot = AttentionCenterSnapshot([
      ...mapPaidLeaveAttention(leave),
      mapAttentionNotification(notice(NotificationBusinessState.completed)),
    ], now: DateTime(2026, 10, 8));
    expect(snapshot.unresolvedCount, 0);
    expect(snapshot.items.single.state, AttentionCenterState.completed);
  });
  test('documents do not deduplicate unrelated notification targets', () {
    final items = mapRequiredDocumentAttention({'missing_names': ['免許証', '資格証']});
    expect(items.length, 2);
    expect(items.first.actionId, isNull);
    expect(items.first.metadata['document_name'], '免許証');
    expect(items.first.deduplicationKey, isNot(items.last.deduplicationKey));
  });
  test('generation issues retain exact payload and do not invent deadline', () {
    final items = mapGenerationAttention({'issues': [{'type': 'missing_rate',
      'key': 'worker-a', 'message': '単価を設定', 'action_key': 'payroll_settings',
      'action_id': 'worker-a'}]});
    expect(items.single.metadata['type'], 'missing_rate');
    expect(items.single.metadata['key'], 'worker-a');
    expect(items.single.actionId, 'worker-a');
    expect(items.single.deadline, isNull);
  });
  test('unavailable actions remain listed without inflating pending count', () {
    final snapshot = AttentionCenterSnapshot(mapPaidLeaveAttention(leave,
      availableActionKeys: {'document_register'}), now: DateTime(2026, 10, 8));
    expect(snapshot.items.length, 1);
    expect(snapshot.unresolvedCount, 0);
    expect(mapGenerationAttention(null), isEmpty);
    expect(mapRequiredDocumentAttention({}), isEmpty);
  });
}
