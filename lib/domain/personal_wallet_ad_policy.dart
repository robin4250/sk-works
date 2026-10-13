class PersonalWalletAdPolicy {
  const PersonalWalletAdPolicy._();

  /// Company/workspace use stays ad-free. Ads are eligible only in the future
  /// free personal-wallet mode.
  static bool adsEligible({
    required bool personalFreeMode,
    required bool activeCompanyWorkspace,
  }) =>
      personalFreeMode && !activeCompanyWorkspace;

  /// Sensitive wallet/work data must never be used as ad-targeting input.
  static const forbiddenTargetingData = <String>{
    'qualification',
    'qualification_certificate',
    'personal_document',
    'identity_document',
    'my_number',
    'attendance_history',
    'payroll',
  };
}
