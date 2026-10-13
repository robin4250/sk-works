import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/notifications/notification_business_status.dart';

void main() {
  Map<String, Object?> value({Object? own = false, bool all = false}) => {
    'period_start': '2026-09-01',
    'reviewers': [{'user_id': 'reviewer-a'}, {'user_id': 'reviewer-b'}],
    'reviewer_confirmed': own,
    'confirmed': all,
  };
  NotificationBusinessState state(Object? raw, {String? user = 'reviewer-a', String period = '2026-09-01'}) =>
      payrollNotificationState(expectedPeriod: period, currentUserId: user, value: raw);

  test('own completed task stays completed while others are pending', () {
    expect(state(value(own: true)), NotificationBusinessState.completed);
    expect(state(value(own: false)), NotificationBusinessState.pending);
    expect(state(value(own: null, all: true)), NotificationBusinessState.unknown);
  });
  test('non-assigned viewers only see proven overall completion', () {
    expect(state(value(), user: 'other'), NotificationBusinessState.unknown);
    expect(state(value(all: true), user: 'other'), NotificationBusinessState.completed);
  });
  test('wrong month and missing identity never reuse another task status', () {
    expect(state(value(own: true), period: '2026-10-01'), NotificationBusinessState.unknown);
    expect(state(value(own: true), user: null), NotificationBusinessState.unknown);
    expect(state(null), NotificationBusinessState.unknown);
    expect(state({'period_start': '2026-09-01', 'confirmed': true}), NotificationBusinessState.unknown);
  });
}
