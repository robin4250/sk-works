import 'dart:async';
import 'dart:convert';

import 'admin_saved_qualification_photo_contract.dart';
import 'admin_saved_qualification_photo_prepare_readiness.dart';
import 'admin_saved_qualification_photo_submission_repository.dart';

/// An in-memory view only. Never persist or log its token.
class QualificationPhotoRpcSession {
  const QualificationPhotoRpcSession({
    required this.actorId,
    required this.companyId,
    required this.targetId,
    required this.accessToken,
    required this.active,
  });
  final String? actorId, companyId, targetId, accessToken;
  final bool active;
  @override
  String toString() => 'QualificationPhotoRpcSession(redacted)';
}

typedef QualificationPhotoPinnedTransport = Future<Object?> Function(
  String functionName,
  Map<String, dynamic> params,
  Map<String, String> headers,
);

/// Disconnected, default-OFF session guard for the existing submission contract.
/// It cannot cancel an HTTP write already sent, refresh tokens, or grant access.
class QualificationPhotoSessionRpc {
  QualificationPhotoSessionRpc({
    required QualificationPhotoRpcSession Function() current,
    required QualificationPhotoPinnedTransport transport,
    bool enabled = false,
  }) : _current = current,
       _initial = current(),
       _transport = transport,
       _enabled = enabled;

  static const functionName = 'personal_qualification_submission';
  static const _reads = {
    'admin_saved_photo_capability',
    'admin_saved_photo_prepare_readiness',
  };
  static const _dataActions = {
    'prepare_admin_saved_photos',
    'get_photos',
    'submit',
    'cancel_photos',
  };
  final QualificationPhotoRpcSession Function() _current;
  final QualificationPhotoRpcSession _initial;
  final QualificationPhotoPinnedTransport _transport;
  final bool _enabled;
  final _changes =
      StreamController<AdminSavedQualificationPhotoSubmissionScope>.broadcast(
        sync: true,
      );
  bool _revoked = false, _disposed = false, _busy = false;
  String? _requestId;

  Stream<AdminSavedQualificationPhotoSubmissionScope> get scopeChanges =>
      _changes.stream;

  bool _matches(QualificationPhotoRpcSession value) =>
      value.active &&
      _initial.active &&
      value.actorId == _initial.actorId &&
      value.companyId == _initial.companyId &&
      value.targetId == _initial.targetId &&
      value.accessToken == _initial.accessToken;

  bool get _active {
    if (!_enabled || _revoked || _disposed) return false;
    try {
      if (!_matches(_current()) ||
          !AdminSavedQualificationPhotoCapability.isUuid(_initial.actorId) ||
          !AdminSavedQualificationPhotoCapability.isUuid(_initial.companyId) ||
          !AdminSavedQualificationPhotoCapability.isUuid(_initial.targetId) ||
          (_initial.accessToken?.isEmpty ?? true)) {
        invalidate();
        return false;
      }
      return true;
    } catch (_) {
      invalidate();
      return false;
    }
  }

  AdminSavedQualificationPhotoSubmissionScope scope() =>
      AdminSavedQualificationPhotoSubmissionScope(
        actorId: _initial.actorId,
        companyId: _initial.companyId,
        targetId: _initial.targetId,
        active: _active,
      );

  /// Caller delivers auth/context events synchronously, including token refresh.
  void observe(QualificationPhotoRpcSession event) {
    if (!_matches(event)) invalidate();
  }

  /// Background, stream error/done and any observed mismatch are sticky.
  void invalidate() {
    if (_revoked || _disposed) return;
    _revoked = true;
    _changes.add(
      AdminSavedQualificationPhotoSubmissionScope(
        actorId: _initial.actorId,
        companyId: _initial.companyId,
        targetId: _initial.targetId,
        active: false,
      ),
    );
  }

  void _check() {
    if (!_active) {
      throw StateError('写真やログイン状態が変わりました。元の画面から開き直してください。');
    }
  }

  Never _reject() {
    invalidate();
    throw StateError('資格写真の対象・権限・対応状況を確認できません。開き直してください。');
  }

  Future<Object?> _raw(String action, Map<String, dynamic> data) async {
    _check();
    if (!_reads.contains(action) && !_dataActions.contains(action)) _reject();
    // Freeze all nested data before an await; caller edits cannot retarget a send.
    final copied = jsonDecode(jsonEncode(data)) as Map<String, dynamic>;
    final params = <String, dynamic>{'p_action': action, 'p_data': copied};
    Object? result;
    try {
      result = await _transport(functionName, params, {
        'Authorization': 'Bearer ${_initial.accessToken!}',
      });
    } catch (_) {
      _check();
      rethrow;
    }
    _check();
    return result;
  }

  Future<AdminSavedQualificationPhotoAuthorization> authorization() async {
    final company = _initial.companyId, actor = _initial.actorId;
    _check();
    final capability = AdminSavedQualificationPhotoCapability.parse(
      await _raw('admin_saved_photo_capability', {'company_id': company}),
      companyId: company!,
      actorId: actor!,
    );
    if (!capability.matchesScope(companyId: company, actorId: actor)) _reject();
    final readiness = AdminSavedQualificationPhotoPrepareReadiness.parse(
      await _raw(AdminSavedQualificationPhotoPrepareReadiness.action, {
        'company_id': company,
      }),
      companyId: company,
      actorId: actor,
    );
    _check();
    if (!readiness.matchesScope(companyId: company, actorId: actor)) _reject();
    return (capability: capability, readiness: readiness);
  }

  void _result(Object? raw, String requestId) {
    if (raw is! Map ||
        raw['id'] != requestId ||
        raw['requested_by'] != _initial.actorId ||
        raw['target_id'] != _initial.targetId) {
      _reject();
    }
  }

  /// Closure-compatible with AdminSavedQualificationPhotoSubmissionRepository.rpc.
  Future<Object?> rpc(String action, Map<String, dynamic> data) async {
    _check();
    if (_busy) throw StateError('写真申請の処理中です。');
    _busy = true;
    try {
      return await _send(action, data);
    } finally {
      _busy = false;
    }
  }

  Future<Object?> _send(String action, Map<String, dynamic> data) async {
    _check();
    if (!_dataActions.contains(action)) _reject();
    // Copy before readiness awaits; the outer repository may hold mutable maps.
    final payload = jsonDecode(jsonEncode(data)) as Map<String, dynamic>;
    final prepare = action == 'prepare_admin_saved_photos';
    final id = payload[prepare ? 'request_id' : 'id'];
    if (!AdminSavedQualificationPhotoCapability.isUuid(
          id is String ? id : null,
        ) ||
        (prepare &&
            (payload['company_id'] != _initial.companyId ||
                payload['target_id'] != _initial.targetId)) ||
        (!prepare && (payload.length != 1 || !payload.containsKey('id'))) ||
        (_requestId != null && id != _requestId))
      _reject();
    await authorization();
    _check();
    // Recovery may start at get. A first submit/cancel must first prove its
    // receipt belongs to this actor and target, never another owned target.
    if (!prepare && action != 'get_photos' && _requestId == null) {
      final before = await _raw('get_photos', {'id': id});
      _result(before, id as String);
      _requestId = id;
    }
    final raw = await _raw(action, payload);
    _result(raw, id as String);
    _requestId = id;
    return raw;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    invalidate();
    _disposed = true;
    await _changes.close();
  }
}
