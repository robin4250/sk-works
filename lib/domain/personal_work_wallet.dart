enum WorkDataOwnership {
  personal,
  company,
  sharedHistory,
}

class PersonalWorkWalletPolicy {
  const PersonalWorkWalletPolicy._();

  static WorkDataOwnership ownershipFor(String dataKey) => switch (dataKey) {
        'profile' ||
        'sko_personal_id' ||
        'qualification' ||
        'qualification_certificate' ||
        'personal_document' =>
          WorkDataOwnership.personal,
        'payroll' ||
        'invoice' ||
        'approval_history' ||
        'company_admin_data' =>
          WorkDataOwnership.company,
        'attendance_history' || 'site_history' =>
          WorkDataOwnership.sharedHistory,
        _ => WorkDataOwnership.company,
      };

  static bool survivesEmploymentDisconnect(String dataKey) =>
      ownershipFor(dataKey) != WorkDataOwnership.company;

  static bool canShareWithNewCompany(String dataKey) =>
      ownershipFor(dataKey) == WorkDataOwnership.personal;
}
