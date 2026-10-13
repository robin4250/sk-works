enum EmploymentDisconnectDestination {
  anotherCompanyWorkspace,
  personalWorkspace,
}

class EmploymentDisconnectTransition {
  const EmploymentDisconnectTransition._();

  static EmploymentDisconnectDestination destination({
    required int remainingActiveCompanyMemberships,
  }) =>
      remainingActiveCompanyMemberships > 0
          ? EmploymentDisconnectDestination.anotherCompanyWorkspace
          : EmploymentDisconnectDestination.personalWorkspace;

  static const personalModeTitle = '会社との連携が終了しました';
  static const personalModeMessage =
      'SKOアプリはこのままご利用いただけます。'
      '個人SKO ID、資格・資格証、本人所有の書類などは'
      '「わたしの仕事データ」に引き続き保存されます。'
      '転職時の引継ぎや、独立・起業して会社を作る際にも利用できます。';
}
