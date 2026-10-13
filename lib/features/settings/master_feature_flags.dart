/// Platform-level feature availability controlled by SKO master operations.
///
/// Core capabilities (authentication, security, attendance integrity) are not
/// represented here and therefore cannot be disabled accidentally.
enum MasterFeature {
  paidLeave,
  qualifications,
  documents,
  vehicleManagement,
  routeAssignment,
  expenseClaims,
}

class MasterFeatureFlags {
  const MasterFeatureFlags(this.disabled);

  final Set<MasterFeature> disabled;

  bool isEnabled(MasterFeature feature) => !disabled.contains(feature);

  MasterFeatureFlags withEnabled(MasterFeature feature, bool enabled) {
    final next = Set<MasterFeature>.of(disabled);
    if (enabled) {
      next.remove(feature);
    } else {
      next.add(feature);
    }
    return MasterFeatureFlags(next);
  }

  static const allEnabled = MasterFeatureFlags(<MasterFeature>{});
}
