class SettlementAccessPolicy {
  const SettlementAccessPolicy._();

  static bool canAccess({
    required String role,
    required bool delegatedSettlementPermission,
    required bool secondFactorVerified,
  }) {
    final administrator = role == 'owner' || role == 'admin';
    final delegatedSubAdmin =
        role == 'sub_admin' && delegatedSettlementPermission;
    return (administrator || delegatedSubAdmin) && secondFactorVerified;
  }

  static bool shouldShowEntry({
    required String role,
    required bool delegatedSettlementPermission,
  }) =>
      role == 'owner' ||
      role == 'admin' ||
      (role == 'sub_admin' && delegatedSettlementPermission);
}
