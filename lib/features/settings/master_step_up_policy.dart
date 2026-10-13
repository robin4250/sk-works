class MasterStepUpPolicy {
  const MasterStepUpPolicy._();

  static const sessionDuration = Duration(minutes: 15);

  static bool requiresFreshAuthentication({
    required bool isMasterAdmin,
    required bool trustedDevice,
    required bool biometricVerified,
    required bool secondPasswordVerified,
    required DateTime? verifiedAt,
    required DateTime now,
  }) {
    if (!isMasterAdmin ||
        !trustedDevice ||
        !biometricVerified ||
        !secondPasswordVerified ||
        verifiedAt == null) {
      return true;
    }
    return now.difference(verifiedAt) >= sessionDuration;
  }

  static bool shouldClearOnAppExit() => true;
}
