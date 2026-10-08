import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/notifications/attention_center_item.dart';

void main() {
  final now = DateTime(2026, 10, 8);
  AttentionCenterItem item(String id, {String source = 'notification', String? key,
    String? target, AttentionCenterState state = AttentionCenterState.pending,
    bool read = false, DateTime? due, int rank = 0, String? reviewer, String? month}) =>
      AttentionCenterItem(id: id, source: source, title: id, state: state,
        actionKey: key, actionId: target, read: read, deadline: due,
        evidenceRank: rank, payrollReviewerId: reviewer, payrollMonth: month);

  test('reading does not complete work; unknown and history remain without counting', () {
    final snapshot = AttentionCenterSnapshot([
      item('read-pending', read: true), item('completed', state: AttentionCenterState.completed),
      item('unknown', state: AttentionCenterState.unknown),
    ], now: now);
    expect(snapshot.items.length, 3);
    expect(snapshot.unresolvedCount, 1);
  });
  test('exact target merges task and message; different targets stay distinct', () {
    final snapshot = AttentionCenterSnapshot([
      item('notice', key: 'paid_leave_request', target: 'batch-a'),
      item('task', source: 'paid_leave', key: 'paid_leave_request', target: 'batch-a',
        state: AttentionCenterState.completed, rank: 10),
      item('other', key: 'paid_leave_request', target: 'batch-b'),
      item('untargeted', source: 'documents'), item('untargeted', source: 'tutorial'),
    ], now: now);
    expect(snapshot.items.length, 4);
    expect(snapshot.items.any((entry) => entry.id == 'task'), isTrue);
    expect(snapshot.unresolvedCount, 3);
  });
  test('explicit payroll reviewer and month deduplicate without inferring month', () {
    final snapshot = AttentionCenterSnapshot([
      item('a', key: 'payroll_review', target: 'statement-a', reviewer: 'user-a', month: '2026-09'),
      item('b', source: 'task', key: 'payroll_review', target: 'statement-b', reviewer: 'user-a', month: '2026-09'),
      item('c', key: 'payroll_review', target: 'statement-c', reviewer: 'user-a', month: '2026-10'),
      item('d', key: 'payroll_review', target: 'statement-d', reviewer: 'user-b', month: '2026-09'),
      item('e', key: 'payroll_review', target: 'statement-e'),
    ], now: now);
    expect(snapshot.items.length, 4);
  });
  test('orders overdue, upcoming, undated, unknown, history, information', () {
    final snapshot = AttentionCenterSnapshot([
      item('information', state: AttentionCenterState.information),
      item('history', state: AttentionCenterState.completed),
      item('undated'), item('unknown', state: AttentionCenterState.unknown),
      item('later', due: now.add(const Duration(days: 8))),
      item('soon', due: now.add(const Duration(days: 1))),
      item('overdue', due: now.subtract(const Duration(days: 1))),
    ], now: now);
    expect(snapshot.items.map((entry) => entry.id),
      ['overdue', 'soon', 'later', 'undated', 'unknown', 'history', 'information']);
    expect(snapshot.items.singleWhere((entry) => entry.id == 'undated').deadline, isNull);
  });
}
