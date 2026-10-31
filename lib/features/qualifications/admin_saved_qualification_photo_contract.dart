/// Review-only management capability. Never substitutes for server write checks.
class AdminSavedQualificationPhotoCapability {
  const AdminSavedQualificationPhotoCapability._({
    required this.available,
    required this.companyId,
    required this.actorId,
    required this.maxPhotos,
  });

  static const unavailable = AdminSavedQualificationPhotoCapability._(
    available: false,
    companyId: null,
    actorId: null,
    maxPhotos: 0,
  );
  final bool available;
  final String? companyId;
  final String? actorId;
  final int maxPhotos;

  static bool isUuid(String? value) =>
      value != null &&
      RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      ).hasMatch(value);

  bool matchesScope({required String? companyId, required String? actorId}) =>
      available && this.companyId == companyId && this.actorId == actorId;

  static AdminSavedQualificationPhotoCapability parse(
    Object? raw, {
    required String companyId,
    required String actorId,
  }) {
    const keys = {
      'version',
      'expected_photo_paths_required',
      'contract',
      'company_id',
      'actor_id',
      'photo_submission_available',
      'photo_upload_allowed',
      'max_photos',
      'self_approval_allowed',
    };
    if (!isUuid(companyId) ||
        !isUuid(actorId) ||
        raw is! Map ||
        raw.length != keys.length ||
        !raw.keys.every(keys.contains) ||
        raw['version'] is! int ||
        raw['version'] != 2 ||
        raw['expected_photo_paths_required'] != true ||
        raw['contract'] != 'qualification_admin_saved_photos' ||
        raw['company_id'] != companyId ||
        raw['actor_id'] != actorId ||
        raw['photo_submission_available'] is! bool ||
        raw['photo_upload_allowed'] != false ||
        raw['self_approval_allowed'] != false ||
        raw['max_photos'] is! int ||
        raw['max_photos'] != 20) {
      return unavailable;
    }
    return AdminSavedQualificationPhotoCapability._(
      available: raw['photo_submission_available'] == true,
      companyId: companyId,
      actorId: actorId,
      maxPhotos: 20,
    );
  }
}
