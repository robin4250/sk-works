import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/domain/personal_company_connection.dart';

void main() {
  test('person can request a company and company can invite a person', () {
    expect(
      PersonalCompanyConnectionDirection.values,
      contains(PersonalCompanyConnectionDirection.personRequestsCompany),
    );
    expect(
      PersonalCompanyConnectionDirection.values,
      contains(PersonalCompanyConnectionDirection.companyInvitesPerson),
    );
  });

  test('both sides approve and personal data is not exposed by discovery', () {
    const request = PersonalCompanyConnectionRequest(
      id: 'r1',
      personalAccountId: 'p1',
      companyId: 'c1',
      direction: PersonalCompanyConnectionDirection.companyInvitesPerson,
      status: PersonalCompanyConnectionStatus.pending,
      requestedPersonalDataKeys: <String>{'qualification'},
    );
    expect(request.requiresPersonApproval, isTrue);
    expect(request.requiresCompanyApproval, isTrue);
    expect(PersonalCompanyDiscoveryPolicy.personAppearsInCompanySearch(), isFalse);
    expect(PersonalCompanyDiscoveryPolicy.employerInviteUsesPersonalSkoId(), isTrue);
  });
}
