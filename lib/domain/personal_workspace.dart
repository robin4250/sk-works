enum WorkspaceKind {
  personal,
  company,
}

class SkoWorkspace {
  const SkoWorkspace({
    required this.id,
    required this.kind,
    required this.displayName,
    this.companyId,
  });

  final String id;
  final WorkspaceKind kind;
  final String displayName;
  final String? companyId;
}

class PersonalWorkspacePolicy {
  const PersonalWorkspacePolicy._();

  static bool personalWorkspaceAlwaysExists() => true;

  /// Leaving a company disconnects only that membership. The personal
  /// workspace and personal-owned data remain.
  static bool deletePersonalWorkspaceOnEmploymentEnd() => false;

  /// A user may later attach another employer or create a company workspace
  /// without replacing the personal account.
  static bool supportsMultipleCompanyWorkspaces() => true;
}
