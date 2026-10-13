import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/notifications/app_notification_repository.dart';
import 'package:sk_works/features/notifications/attention_center_item.dart';
import 'package:sk_works/features/notifications/attention_center_repository.dart';
import 'package:sk_works/features/notifications/notifications_page.dart';
import 'package:sk_works/features/notifications/notification_bell.dart';
import 'package:sk_works/features/route_billing/route_billing_quantity_approvals_page.dart';

void main() {
  const id = '12345678-1234-1234-1234-123456789abc';
  final rows = [{'id': id, 'status': 'pending', 'customer_name': '登録取引会社',
    'worker_name': '登録社員', 'work_date': '2026-10-12',
    'created_at': '2026-10-14T00:00:00Z'}];

  test('pending route quantity remains actionable without a home approval shortcut', () {
    final item = mapRouteBillingQuantityAttention(rows).single;
    expect(item.actionId, id);
    expect(item.actionKey, 'route_billing_quantity_request');
    expect(item.targetName, '登録取引会社');
    expect(item.targetDate, DateTime(2026, 10, 12));
    expect(item.actionable, isTrue);
    final snapshot = AttentionCenterSnapshot([item], now: DateTime(2026, 10, 14));
    expect(snapshot.unresolvedCount, 1);
    final destination = notificationDestination(AppNotificationRecord(
      id: '', kind: item.source, title: item.title, body: item.body,
      createdAt: DateTime(2026, 10, 14), read: true,
      actionKey: item.actionKey, actionId: item.actionId));
    expect(destination, isA<RouteBillingQuantityApprovalsPage>()
      .having((page) => page.initialRequestId, 'exact saved request', id));
  });

  test('bell counts a pending request once with a matching unread notification', () {
    final pending = mapRouteBillingQuantityAttention(rows);
    final notice = AppNotificationRecord(id: 'notice', kind: 'approval',
      title: 'approval', body: '', createdAt: DateTime(2026, 10, 14),
      read: false, actionKey: 'route_billing_quantity_request', actionId: id);
    expect(routeAwareNotificationBadgeCount([], pending), 1);
    expect(routeAwareNotificationBadgeCount([notice], pending), 1);
    expect(routeAwareNotificationBadgeCount([], []), 0);
  });

  test('approved, missing and malformed rows never become synthetic pending tasks', () {
    expect(mapRouteBillingQuantityAttention(null), isEmpty);
    expect(mapRouteBillingQuantityAttention([
      {...rows.single, 'status': 'approved'},
      {...rows.single, 'id': ''}, {...rows.single, 'id': 'not-a-request'}, 'invalid',
    ]), isEmpty);
  });
}
