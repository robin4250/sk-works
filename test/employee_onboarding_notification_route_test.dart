import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/auth/employee_onboarding_approvals_page.dart';
import 'package:sk_works/features/notifications/app_notification_repository.dart';
import 'package:sk_works/features/notifications/notifications_page.dart';

void main() {
  test('employee registration notification opens only its own approval', () {
    const inviteId = '11111111-1111-1111-1111-111111111111';
    AppNotificationRecord notice(String? target) => AppNotificationRecord(
      id: 'notification',
      kind: 'approval',
      title: '',
      body: '',
      createdAt: DateTime(2026),
      read: false,
      actionKey: 'employee_onboarding_approval',
      actionId: target,
    );

    final destination = notificationDestination(notice(inviteId));
    expect(destination, isA<EmployeeOnboardingApprovalsPage>());
    expect((destination as EmployeeOnboardingApprovalsPage).initialInviteId, inviteId);
    expect(notificationDestination(notice(null)), isNull);
    expect(notificationDestination(notice('invalid')), isNull);
  });
}
