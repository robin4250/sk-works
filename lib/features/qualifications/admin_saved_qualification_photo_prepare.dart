import 'admin_saved_qualification_photo_contract.dart';
import 'admin_saved_qualification_photo_draft.dart';
import 'admin_saved_qualification_photo_prepare_readiness.dart';

/// Frozen local request values; it neither sends nor approves a photo change.
/// The caller must recheck lifecycle/scope before using [toPayload].
class AdminSavedQualificationPhotoPrepare {
  AdminSavedQualificationPhotoPrepare._({
    required this.companyId,
    required this.actorId,
    required this.targetId,
    required this.requestId,
    required this.savedPaths,
    required this.selectedPaths,
  });

  factory AdminSavedQualificationPhotoPrepare.fromDraft({
    required AdminSavedQualificationPhotoDraft draft,
    required AdminSavedQualificationPhotoCapability capability,
    required AdminSavedQualificationPhotoPrepareReadiness readiness,
    required String requestId,
    required bool scopeActive,
    required String? currentCompanyId,
    required String? currentActorId,
    required String? currentTargetId,
    required Iterable<String> currentSavedPaths,
  }) {
    final command = AdminSavedQualificationPhotoPrepare._(
      companyId: draft.companyId,
      actorId: draft.actorId,
      targetId: draft.targetId,
      requestId: requestId,
      savedPaths: List.unmodifiable(draft.savedPaths),
      selectedPaths: List.unmodifiable(draft.selectedPaths),
    );
    command._check(
      capability: capability,
      readiness: readiness,
      scopeActive: scopeActive,
      companyId: currentCompanyId,
      actorId: currentActorId,
      targetId: currentTargetId,
      savedPaths: currentSavedPaths,
    );
    return command;
  }

  final String companyId, actorId, targetId, requestId;
  final List<String> savedPaths, selectedPaths;
  bool _revoked = false;

  static bool _orderedEqual(Iterable<String> left, List<String> right) {
    final values = left.toList(growable: false);
    if (values.length != right.length) return false;
    for (var i = 0; i < values.length; i++) {
      if (values[i] != right[i]) return false;
    }
    return true;
  }

  void _check({
    required AdminSavedQualificationPhotoCapability capability,
    required AdminSavedQualificationPhotoPrepareReadiness readiness,
    required bool scopeActive,
    required String? companyId,
    required String? actorId,
    required String? targetId,
    required Iterable<String> savedPaths,
  }) {
    if (_revoked ||
        !scopeActive ||
        !AdminSavedQualificationPhotoCapability.isUuid(this.companyId) ||
        !AdminSavedQualificationPhotoCapability.isUuid(this.actorId) ||
        !AdminSavedQualificationPhotoCapability.isUuid(this.targetId) ||
        !AdminSavedQualificationPhotoCapability.isUuid(requestId) ||
        companyId != this.companyId ||
        actorId != this.actorId ||
        targetId != this.targetId ||
        !capability.matchesScope(companyId: companyId, actorId: actorId) ||
        !readiness.matchesScope(companyId: companyId, actorId: actorId) ||
        capability.maxPhotos != 20 ||
        !_orderedEqual(savedPaths, this.savedPaths)) {
      _revoked = true;
      throw StateError('写真やログイン状態が変わりました。元の画面から開き直してください。');
    }
    if (this.savedPaths.isEmpty ||
        this.savedPaths.length > capability.maxPhotos ||
        this.savedPaths.toSet().length != this.savedPaths.length ||
        this.savedPaths.any((path) => path.trim().isEmpty) ||
        selectedPaths.length > capability.maxPhotos ||
        selectedPaths.toSet().length != selectedPaths.length ||
        selectedPaths.any((path) => !this.savedPaths.contains(path))) {
      throw StateError('保存済み資格写真の選択を確認できません。');
    }
  }

  /// Only the backend's ordered baseline contract may consume this payload.
  /// Empty photo_slots requests removal of every attachment, never the record.
  Map<String, dynamic> toPayload({
    required AdminSavedQualificationPhotoCapability currentCapability,
    required AdminSavedQualificationPhotoPrepareReadiness currentReadiness,
    required bool scopeActive,
    required String? currentCompanyId,
    required String? currentActorId,
    required String? currentTargetId,
    required Iterable<String> currentSavedPaths,
  }) {
    _check(
      capability: currentCapability,
      readiness: currentReadiness,
      scopeActive: scopeActive,
      companyId: currentCompanyId,
      actorId: currentActorId,
      targetId: currentTargetId,
      savedPaths: currentSavedPaths,
    );
    return Map.unmodifiable({
      'company_id': companyId,
      'target_id': targetId,
      'request_id': requestId,
      'expected_photo_paths': savedPaths,
      'photo_slots': List.unmodifiable([
        for (final path in selectedPaths)
          Map<String, String>.unmodifiable({'existing_path': path}),
      ]),
    });
  }
}
