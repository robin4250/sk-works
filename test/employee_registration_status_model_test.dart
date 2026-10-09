import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/people/employee_invite_repository.dart';
void main() {
  InitialRegistrationEmployee employee(Map row) => InitialRegistrationEmployee(
    id: 'worker', name: 'Employee', phone: '090', invited: true,
    registrationStatus: EmployeeRegistrationStatus.fromRow('company', row),
  );
  test('linked account and pending approval remain incomplete', () {
    expect(employee({'invitation_status': 'approval_pending', 'initial_registration_completed': false}).completed, isFalse);
    expect(employee({'invitation_status': 'approved', 'initial_registration_completed': true}).completed, isFalse);
    expect(employee({'invitation_status': 'approved', 'approved_at': '2026-10-09', 'initial_registration_completed': true}).completed, isTrue);
  });
  test('invitation identity is independent of linked account', () {
    final created = InitialRegistrationEmployee(
      id: 'worker', name: 'Employee', phone: '090', invited: false,
      registrationStatus: EmployeeRegistrationStatus.fromRow('company', {
        'invitation_id': 'invite', 'delivery_state': 'unknown',
      }),
    );
    expect(created.hasInvitation, isTrue);
    expect(created.needsSending, isTrue);
    expect(created.completed, isFalse);
    expect(created.registrationStatus!.companyId, 'company');
    expect(created.registrationStatus!.invitationId, 'invite');
  });
  test('manual sending is separate from completion and unknown remains eligible', () {
    final sent = employee({'invitation_status': 'invited', 'invitation_id': 'invite', 'delivery_state': 'manual_sent'});
    expect(sent.completed, isFalse);
    expect(sent.needsSending, isFalse);
    expect(employee({'delivery_state': 'unknown'}).needsSending, isTrue);
    const unavailable = InitialRegistrationEmployee(id: 'worker', name: 'Employee', phone: '090', invited: true);
    expect(unavailable.completed, isFalse);
    expect(unavailable.needsSending, isTrue);
  });
}
