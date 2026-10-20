import 'admin_saved_qualification_photo_contract.dart';

/// Dedicated read response. Legacy management/personal capability is insufficient.
class AdminSavedQualificationPhotoPrepareReadiness {
  const AdminSavedQualificationPhotoPrepareReadiness._({
    required this.available,
    required this.companyId,
    required this.actorId,
  });

  static const action = 'admin_saved_photo_prepare_readiness';
  static const prepareAction = 'prepare_admin_saved_photos';
  static const unavailable = AdminSavedQualificationPhotoPrepareReadiness._(
    available: false,
    companyId: null,
    actorId: null,
  );
  final bool available;
  final String? companyId, actorId;

  bool matchesScope({required String? companyId, required String? actorId}) =>
      available && this.companyId == companyId && this.actorId == actorId;

  static AdminSavedQualificationPhotoPrepareReadiness parse(
    Object? raw, {
    required String companyId,
    required String actorId,
  }) {
    const keys = {
      'version',
      'contract',
      'company_id',
      'actor_id',
      'baseline_guard_version',
      'prepare_action',
      'photo_submission_available',
      'photo_upload_allowed',
      'max_photos',
      'self_approval_allowed',
    };
    if (!AdminSavedQualificationPhotoCapability.isUuid(companyId) ||
        !AdminSavedQualificationPhotoCapability.isUuid(actorId) ||
        raw is! Map ||
        raw.length != keys.length ||
        !raw.keys.every(keys.contains) ||
        raw['version'] is! int ||
        raw['version'] != 1 ||
        raw['contract'] != 'qualification_admin_photo_prepare_baseline' ||
        raw['company_id'] != companyId ||
        raw['actor_id'] != actorId ||
        raw['baseline_guard_version'] is! int ||
        raw['baseline_guard_version'] != 1 ||
        raw['prepare_action'] != prepareAction ||
        raw['photo_submission_available'] is! bool ||
        raw['photo_upload_allowed'] != false ||
        raw['max_photos'] is! int ||
        raw['max_photos'] != 20 ||
        raw['self_approval_allowed'] != false)
      return unavailable;
    return AdminSavedQualificationPhotoPrepareReadiness._(
      available: raw['photo_submission_available'] == true,
      companyId: companyId,
      actorId: actorId,
    );
  }
}
