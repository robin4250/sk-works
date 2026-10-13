enum ManagedResource {
  site,
  vehicle,
  route,
}

class ResourceManagementPermission {
  const ResourceManagementPermission._();

  static bool canViewOrUse({required bool isCompanyMember}) => isCompanyMember;

  static bool canManage({
    required String role,
    required ManagedResource resource,
    Set<ManagedResource> delegated = const <ManagedResource>{},
  }) {
    if (role == 'owner' ||
        role == 'admin' ||
        role == 'sub_admin' ||
        role == 'manager') {
      return true;
    }
    if (resource == ManagedResource.vehicle ||
        resource == ManagedResource.route) {
      return false;
    }
    return delegated.contains(resource);
  }

  /// Historical references should survive operational removal.
  static bool shouldSoftDisableInsteadOfDelete() => true;
}
