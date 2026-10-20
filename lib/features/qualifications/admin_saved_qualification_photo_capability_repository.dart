import 'dart:async';

import '../../data/supabase_backend.dart';
import 'admin_saved_qualification_photo_contract.dart';
import 'admin_saved_qualification_photo_prepare_readiness.dart';

/// Unconnected preparation: reads only the dedicated management capability.
/// The gate defaults OFF. Recreate after scope changes; invalidation is sticky.
class AdminSavedQualificationPhotoCapabilityRepository {
  AdminSavedQualificationPhotoCapabilityRepository.forTesting({
    required String? Function() actor,
    required String? Function() companyId,
    required Stream<String?> actorChanges,
    required Stream<String?> companyChanges,
    required Future<Object?> Function(String action, Map<String, dynamic> data)
    rpc,
    bool enabled = false,
  }) : _actor = actor,
       _company = companyId,
       _rpc = rpc,
       _enabled = enabled,
       _initialActor = actor(),
       _initialCompany = companyId() {
    if (!enabled) return;
    _actorSubscription = actorChanges.listen(
      (value) {
        if (value != _initialActor) _revoked = true;
      },
      onError: (Object _) {
        _revoked = true;
      },
      onDone: () {
        _revoked = true;
      },
    );
    _companySubscription = companyChanges.listen(
      (value) {
        if (value != _initialCompany) _revoked = true;
      },
      onError: (Object _) {
        _revoked = true;
      },
      onDone: () {
        _revoked = true;
      },
    );
  }

  static AdminSavedQualificationPhotoCapabilityRepository? maybeCreate({
    required String? Function() companyId,
    required Stream<String?> companyChanges,
    bool enabled = false,
  }) {
    if (!enabled || !SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    return AdminSavedQualificationPhotoCapabilityRepository.forTesting(
      actor: () => client.auth.currentUser?.id,
      companyId: companyId,
      actorChanges: client.auth.onAuthStateChange.map(
        (state) => state.session?.user.id,
      ),
      companyChanges: companyChanges,
      rpc: (action, data) async => client.rpc(
        'personal_qualification_submission',
        params: {'p_action': action, 'p_data': data},
      ),
      enabled: enabled,
    );
  }

  final String? Function() _actor, _company;
  final String? _initialActor, _initialCompany;
  final Future<Object?> Function(String, Map<String, dynamic>) _rpc;
  final bool _enabled;
  bool _revoked = false;
  StreamSubscription<String?>? _actorSubscription, _companySubscription;

  bool get _current {
    if (!_enabled || _revoked) return false;
    if (_actor() != _initialActor || _company() != _initialCompany) {
      _revoked = true;
      return false;
    }
    return AdminSavedQualificationPhotoCapability.isUuid(_initialActor) &&
        AdminSavedQualificationPhotoCapability.isUuid(_initialCompany);
  }

  bool canUse(AdminSavedQualificationPhotoCapability capability) =>
      _current &&
      capability.matchesScope(
        companyId: _initialCompany,
        actorId: _initialActor,
      );

  Future<AdminSavedQualificationPhotoCapability> capability() async {
    if (!_current) return AdminSavedQualificationPhotoCapability.unavailable;
    try {
      final value = await _rpc('admin_saved_photo_capability', {
        'company_id': _initialCompany,
      });
      if (!_current) return AdminSavedQualificationPhotoCapability.unavailable;
      return AdminSavedQualificationPhotoCapability.parse(
        value,
        companyId: _initialCompany!,
        actorId: _initialActor!,
      );
    } catch (_) {
      // Missing candidate, denial, transport errors: never try personal capability.
      return AdminSavedQualificationPhotoCapability.unavailable;
    }
  }

  Future<AdminSavedQualificationPhotoPrepareReadiness>
  prepareReadiness() async {
    if (!_current) {
      return AdminSavedQualificationPhotoPrepareReadiness.unavailable;
    }
    try {
      final value = await _rpc(
        AdminSavedQualificationPhotoPrepareReadiness.action,
        {'company_id': _initialCompany},
      );
      if (!_current) {
        return AdminSavedQualificationPhotoPrepareReadiness.unavailable;
      }
      return AdminSavedQualificationPhotoPrepareReadiness.parse(
        value,
        companyId: _initialCompany!,
        actorId: _initialActor!,
      );
    } catch (_) {
      // Missing action, denial, or transport failure remains OFF. No fallback.
      return AdminSavedQualificationPhotoPrepareReadiness.unavailable;
    }
  }

  Future<void> dispose() async {
    _revoked = true;
    await _actorSubscription?.cancel();
    await _companySubscription?.cancel();
  }
}
