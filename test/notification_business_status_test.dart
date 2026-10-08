import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/notifications/notification_business_status.dart';

void main() {
  test('unavailable or unrecognized state remains unknown', () {
    expect(NotificationBusinessStatus.fromRows([]).state, NotificationBusinessState.unknown);
    expect(NotificationBusinessStatus.fromRows([{'status': 'draft'}]).state, NotificationBusinessState.unknown);
    expect(NotificationBusinessStatus.fromRows([{'status': 'approved'}, {}]).state, NotificationBusinessState.unknown);
  });
  test('batch completion requires every visible item completed', () {
    expect(NotificationBusinessStatus.fromRows([{'status': 'approved'}, {'status': 'pending'}]).state, NotificationBusinessState.pending);
    expect(NotificationBusinessStatus.fromRows([{'status': 'approved'}, {'status': 'used'}]).state, NotificationBusinessState.completed);
    expect(NotificationBusinessStatus.fromRows([{'status': 'approved'}, {'status': 'rejected'}]).state, NotificationBusinessState.rejected);
  });
  test('target date and person come only from the target row', () {
    final item = NotificationBusinessStatus.fromRows([{'status': 'pending', 'period_start': '2026-09-01', 'workers': {'name': '社員A'}}]);
    expect(item.targetName, '社員A');
    expect(item.targetDate, DateTime(2026, 9, 1));
    expect(NotificationBusinessStatus.fromRows([{'status': 'pending'}]).targetDate, isNull);
  });
}
