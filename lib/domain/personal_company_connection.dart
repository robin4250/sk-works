enum PersonalCompanyConnectionDirection {
  personRequestsCompany,
  companyInvitesPerson,
}

enum PersonalCompanyConnectionStatus {
  pending,
  accepted,
  rejected,
  revoked,
}

class PersonalCompanyConnectionRequest {
  const PersonalCompanyConnectionRequest({
    required this.id,
    required this.personalAccountId,
    required this.companyId,
    required this.direction,
    required this.status,
    required this.requestedPersonalDataKeys,
  });

  final String id;
  final String personalAccountId;
  final String companyId;
  final PersonalCompanyConnectionDirection direction;
  final PersonalCompanyConnectionStatus status;
  final Set<String> requestedPersonalDataKeys;

  bool get requiresPersonApproval => true;
  bool get requiresCompanyApproval => true;
}

class PersonalCompanyDiscoveryPolicy {
  const PersonalCompanyDiscoveryPolicy._();

  /// Company search remains company-only. People are never listed in the
  /// public/company discovery results.
  static bool personAppearsInCompanySearch() => false;

  /// Employer-initiated connection addresses an existing person by their
  /// personal SKO ID; possession of the ID does not grant data access.
  static bool employerInviteUsesPersonalSkoId() => true;
}
