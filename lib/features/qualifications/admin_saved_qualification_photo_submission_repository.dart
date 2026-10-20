import 'dart:async';
import 'dart:convert';

import 'admin_saved_qualification_photo_contract.dart';
import 'admin_saved_qualification_photo_prepare.dart';
import 'admin_saved_qualification_photo_prepare_readiness.dart';

/// The production adapter must persist durably and compare/update atomically.
/// A failed or uncertain write must not be treated as permission to send an RPC.
abstract class AdminSavedQualificationPhotoPendingStore {
  Future<String?> read(String key);
  Future<bool> compareAndSet(String key, String? expected, String? replacement);
}

class AdminSavedQualificationPhotoSubmissionScope {
  const AdminSavedQualificationPhotoSubmissionScope({
    required this.actorId,
    required this.companyId,
    required this.targetId,
    required this.active,
  });
  final String? actorId, companyId, targetId;
  final bool active;
}

typedef AdminSavedQualificationPhotoAuthorization = ({
  AdminSavedQualificationPhotoCapability capability,
  AdminSavedQualificationPhotoPrepareReadiness readiness,
});

/// Only fields actually returned by qualification_photo_submission_result.
class AdminSavedQualificationPhotoSubmissionResult {
  AdminSavedQualificationPhotoSubmissionResult._({
    required this.id,
    required this.targetId,
    required this.requestedBy,
    required this.status,
    required this.cancelled,
    required this.reason,
    required Iterable<String> paths,
  }) : paths = List.unmodifiable(paths);
  final String id, targetId, requestedBy, status;
  final bool cancelled;
  final String? reason;
  final List<String> paths;
  bool get submitted => status == 'pending' || status == 'approved';
}

class AdminSavedQualificationPhotoOutcomeUnknown implements Exception {
  const AdminSavedQualificationPhotoOutcomeUnknown(this.requestId);
  final String requestId;
  @override
  String toString() => '写真申請の結果を確認できません。同じ申請を再確認してください。';
}

/// Disconnected management transport; no production factory, uploads or review.
/// Default OFF. Recovery never submits or cancels without an explicit action.
class AdminSavedQualificationPhotoSubmissionRepository {
  AdminSavedQualificationPhotoSubmissionRepository({
    required AdminSavedQualificationPhotoSubmissionScope Function() scope,
    required Stream<AdminSavedQualificationPhotoSubmissionScope> scopeChanges,
    required Future<AdminSavedQualificationPhotoAuthorization> Function()
    authorization,
    required Future<Object?> Function(String, Map<String, dynamic>) rpc,
    required AdminSavedQualificationPhotoPendingStore store,
    bool enabled = false,
  }) : _scope = scope,
       _initial = scope(),
       _authorization = authorization,
       _rpc = rpc,
       _store = store,
       _enabled = enabled {
    if (!enabled) {
      return;
    }
    _subscription = scopeChanges.listen(
      (value) {
        if (!_matches(value)) {
          _revoked = true;
        }
      },
      onError: (Object _) {
        _revoked = true;
      },
      onDone: () {
        _revoked = true;
      },
    );
  }

  final AdminSavedQualificationPhotoSubmissionScope Function() _scope;
  final AdminSavedQualificationPhotoSubmissionScope _initial;
  final Future<AdminSavedQualificationPhotoAuthorization> Function()
  _authorization;
  final Future<Object?> Function(String, Map<String, dynamic>) _rpc;
  final AdminSavedQualificationPhotoPendingStore _store;
  final bool _enabled;
  StreamSubscription<AdminSavedQualificationPhotoSubmissionScope>?
  _subscription;
  bool _revoked = false, _busy = false;

  bool _matches(AdminSavedQualificationPhotoSubmissionScope value) =>
      value.active &&
      _initial.active &&
      value.actorId == _initial.actorId &&
      value.companyId == _initial.companyId &&
      value.targetId == _initial.targetId;

  void _check() {
    if (!_enabled ||
        _revoked ||
        !_matches(_scope()) ||
        !AdminSavedQualificationPhotoCapability.isUuid(_initial.actorId) ||
        !AdminSavedQualificationPhotoCapability.isUuid(_initial.companyId) ||
        !AdminSavedQualificationPhotoCapability.isUuid(_initial.targetId)) {
      _revoked = true;
      throw StateError('写真やログイン状態が変わりました。元の画面から開き直してください。');
    }
  }

  Future<T> _exclusive<T>(Future<T> Function() operation) async {
    _check();
    if (_busy) {
      throw StateError('写真申請の処理中です。');
    }
    _busy = true;
    try {
      return await operation();
    } finally {
      _busy = false;
    }
  }

  Future<AdminSavedQualificationPhotoAuthorization> _authorized() async {
    _check();
    final value = await _authorization();
    _check();
    if (!value.capability.matchesScope(
          companyId: _initial.companyId,
          actorId: _initial.actorId,
        ) ||
        !value.readiness.matchesScope(
          companyId: _initial.companyId,
          actorId: _initial.actorId,
        )) {
      _revoked = true;
      throw StateError('資格写真の管理権限と対応状況を確認できません。開き直してください。');
    }
    return value;
  }

  String get _key =>
      'sko.admin.qualification.photos.pending.v1.${_initial.actorId}.${_initial.companyId}';

  Future<_Pending?> _load({String? expectedRequestId}) async {
    _check();
    final raw = await _store.read(_key);
    _check();
    if (raw == null) {
      return null;
    }
    final value = _Pending.decode(raw);
    if (value.actorId != _initial.actorId ||
        value.companyId != _initial.companyId ||
        value.targetId != _initial.targetId ||
        (expectedRequestId != null && value.requestId != expectedRequestId)) {
      throw StateError('表示中の写真申請が変わりました。元の対象から再確認してください。');
    }
    return value;
  }

  Future<void> _persist(_Pending value, String? expected) async {
    _check();
    if (!await _store.compareAndSet(_key, expected, value.encoded)) {
      throw StateError('保留中の写真申請が変わりました。同じ申請を再確認してください。');
    }
    _check();
    if (await _store.read(_key) != value.encoded) {
      throw StateError('再確認用の申請情報を保存できませんでした。');
    }
    _check();
  }

  Future<_Pending> _phase(_Pending value, String phase) async {
    final next = value.next(phase);
    await _persist(next, value.encoded);
    return next;
  }

  Future<Object?> _call(String action, Map<String, dynamic> data) async {
    await _authorized();
    _check();
    Object? value;
    try {
      value = await _rpc(action, data);
    } catch (_) {
      _check();
      throw const _TransportFailure();
    }
    _check();
    return value;
  }

  AdminSavedQualificationPhotoSubmissionResult _parse(
    Object? raw,
    _Pending command,
  ) {
    const keys = {
      'version',
      'id',
      'target_id',
      'requested_by',
      'status',
      'cancelled',
      'reason',
      'photo_paths',
      'upload_paths',
    };
    if (raw is! Map ||
        raw.length != keys.length ||
        !raw.keys.every(keys.contains) ||
        raw['version'] is! int ||
        raw['version'] != 1 ||
        raw['id'] != command.requestId ||
        raw['target_id'] != command.targetId ||
        raw['requested_by'] != command.actorId ||
        raw['status'] is! String ||
        !const {
          'draft',
          'pending',
          'approved',
          'rejected',
        }.contains(raw['status']) ||
        raw['cancelled'] is! bool ||
        (raw['cancelled'] == true && raw['status'] != 'rejected') ||
        (raw['reason'] != null && raw['reason'] is! String) ||
        (raw['status'] == 'rejected' &&
            (raw['reason'] is! String ||
                (raw['reason'] as String).trim().isEmpty)) ||
        raw['photo_paths'] is! List ||
        raw['upload_paths'] is! List ||
        (raw['upload_paths'] as List).isNotEmpty) {
      throw StateError('写真申請の保存対象・状態を確認できません。');
    }
    final paths = raw['photo_paths'] as List;
    if (!_orderedEqual(paths, command.selectedPaths)) {
      throw StateError('写真申請の並び順が選択内容と一致しません。');
    }
    return AdminSavedQualificationPhotoSubmissionResult._(
      id: raw['id'] as String,
      targetId: raw['target_id'] as String,
      requestedBy: raw['requested_by'] as String,
      status: raw['status'] as String,
      cancelled: raw['cancelled'] as bool,
      reason: raw['reason'] as String?,
      paths: paths.cast<String>(),
    );
  }

  Future<AdminSavedQualificationPhotoSubmissionResult> _get(
    _Pending command,
  ) async {
    final result = _parse(
      await _call('get_photos', {'id': command.requestId}),
      command,
    );
    if (command.phase == 'confirmed' && result.status == 'draft') {
      throw StateError('確認済み写真申請の状態が戻っています。同じ申請を再確認してください。');
    }
    return result;
  }

  Future<AdminSavedQualificationPhotoSubmissionResult> _writeAndRead(
    String action,
    Map<String, dynamic> data,
    _Pending command,
  ) async {
    Object? raw;
    var transportFailed = false;
    try {
      raw = await _call(action, data);
    } on _TransportFailure {
      transportFailed = true;
    }
    _check();
    if (!transportFailed) {
      final result = _parse(raw, command);
      if ((action == 'submit' && !result.submitted) ||
          (action == 'cancel_photos' &&
              !(result.status == 'rejected' && result.cancelled))) {
        throw StateError('写真申請の処理結果を確認できません。同じ申請を再確認してください。');
      }
    }
    try {
      return await _get(command);
    } catch (error) {
      _check();
      if (error is StateError) {
        rethrow;
      }
      throw AdminSavedQualificationPhotoOutcomeUnknown(command.requestId);
    }
  }

  Future<_Pending> _record(
    _Pending command,
    AdminSavedQualificationPhotoSubmissionResult result,
  ) {
    if (command.phase == 'confirmed' && result.status == 'draft') {
      throw StateError('確認済み写真申請の状態が戻っています。同じ申請を再確認してください。');
    }
    return _phase(command, result.status == 'draft' ? 'prepared' : 'confirmed');
  }

  Future<String?> pendingRequestId() async {
    if (!_enabled) {
      return null;
    }
    await _authorized();
    return (await _load())?.requestId;
  }

  Future<AdminSavedQualificationPhotoSubmissionResult> prepare({
    required AdminSavedQualificationPhotoPrepare command,
    required Iterable<String> currentSavedPaths,
  }) => _exclusive(() async {
    final auth = await _authorized();
    final payload = command.toPayload(
      currentCapability: auth.capability,
      currentReadiness: auth.readiness,
      scopeActive: true,
      currentCompanyId: _initial.companyId,
      currentActorId: _initial.actorId,
      currentTargetId: _initial.targetId,
      currentSavedPaths: currentSavedPaths,
    );
    if (await _load() != null) {
      throw StateError('先に保留中の写真申請を再確認してください。');
    }
    final pending = _Pending.fromCommand(command);
    await _persist(pending, null); // fixed identity BEFORE any mutation RPC
    final result = await _writeAndRead(
      'prepare_admin_saved_photos',
      payload,
      pending,
    );
    await _record(pending, result);
    return result;
  });

  /// Read or repeat the same prepare only. Never silently submits/cancels.
  Future<AdminSavedQualificationPhotoSubmissionResult> recover({
    required String expectedRequestId,
  }) => _exclusive(() async {
    final command = await _load(expectedRequestId: expectedRequestId);
    if (command == null) {
      throw StateError('保留中の写真申請はありません。');
    }
    final result = command.phase == 'prepare_unknown'
        ? await _writeAndRead(
            'prepare_admin_saved_photos',
            command.preparePayload,
            command,
          )
        : await _get(command);
    await _record(command, result);
    return result;
  });

  Future<AdminSavedQualificationPhotoSubmissionResult> submit({
    required String expectedRequestId,
  }) => _exclusive(() async {
    var command = await _load(expectedRequestId: expectedRequestId);
    if (command == null) {
      throw StateError('保留中の写真申請はありません。');
    }
    final before = await _get(command);
    if (before.submitted) {
      await _record(command, before);
      return before;
    }
    if (before.status != 'draft') {
      await _record(command, before);
      throw StateError('下書き以外の写真申請は送信できません。');
    }
    command = await _phase(command, 'submit_unknown');
    final result = await _writeAndRead('submit', {
      'id': command.requestId,
    }, command);
    await _record(command, result);
    if (result.status == 'draft') {
      throw StateError('写真申請の送信は未確認です。同じ申請を再確認してください。');
    }
    return result;
  });

  Future<AdminSavedQualificationPhotoSubmissionResult> cancelDraft({
    required String expectedRequestId,
  }) => _exclusive(() async {
    var command = await _load(expectedRequestId: expectedRequestId);
    if (command == null) {
      throw StateError('保留中の写真申請はありません。');
    }
    final before = await _get(command);
    if (before.status == 'rejected' && before.cancelled) {
      await _record(command, before);
      return before;
    }
    if (before.status != 'draft') {
      await _record(command, before);
      throw StateError('下書き以外の写真申請は取り消せません。');
    }
    command = await _phase(command, 'cancel_unknown');
    final result = await _writeAndRead('cancel_photos', {
      'id': command.requestId,
    }, command);
    await _record(command, result);
    if (result.status != 'rejected' || !result.cancelled) {
      throw StateError('写真申請の取消は未確認です。同じ申請を再確認してください。');
    }
    return result;
  });

  /// Keep a recoverable receipt until the caller explicitly acknowledges it.
  /// No unproven management list/review response is needed to find this request.
  Future<void> acknowledge({required String expectedRequestId}) =>
      _exclusive(() async {
        final command = await _load(expectedRequestId: expectedRequestId);
        if (command == null) {
          throw StateError('保留中の写真申請はありません。');
        }
        final result = await _get(command);
        if (result.status == 'draft') {
          throw StateError('未送信の下書きは先に送信または取消してください。');
        }
        _check();
        if (!await _store.compareAndSet(_key, command.encoded, null)) {
          throw StateError('保留中の写真申請が変わりました。同じ申請を再確認してください。');
        }
        _check();
        if (await _store.read(_key) != null) {
          throw StateError('保留中の写真申請が変わりました。同じ申請を再確認してください。');
        }
        _check();
      });

  Future<void> dispose() async {
    _revoked = true;
    await _subscription?.cancel();
  }
}

bool _orderedEqual(Iterable<Object?> left, List<String> right) {
  final values = left.toList(growable: false);
  if (values.length != right.length) {
    return false;
  }
  for (var i = 0; i < values.length; i++) {
    if (values[i] is! String || values[i] != right[i]) {
      return false;
    }
  }
  return true;
}

class _Pending {
  _Pending._(
    this.actorId,
    this.companyId,
    this.targetId,
    this.requestId,
    List<String> saved,
    List<String> selected,
    this.phase,
    this.revision,
    this.encoded,
  ) : savedPaths = List.unmodifiable(saved),
      selectedPaths = List.unmodifiable(selected);
  final String actorId, companyId, targetId, requestId, phase, encoded;
  final int revision;
  final List<String> savedPaths, selectedPaths;
  static const _phases = {
    'prepare_unknown',
    'prepared',
    'submit_unknown',
    'cancel_unknown',
    'confirmed',
  };
  factory _Pending.fromCommand(AdminSavedQualificationPhotoPrepare command) =>
      _Pending.create(
        command.actorId,
        command.companyId,
        command.targetId,
        command.requestId,
        command.savedPaths,
        command.selectedPaths,
        'prepare_unknown',
        0,
      );
  factory _Pending.create(
    String actor,
    String company,
    String target,
    String request,
    List<String> saved,
    List<String> selected,
    String phase,
    int revision,
  ) => _Pending.decode(
    jsonEncode({
      'version': 1,
      'contract': 'qualification_admin_saved_photo_pending',
      'actor_id': actor,
      'company_id': company,
      'target_id': target,
      'request_id': request,
      'expected_photo_paths': saved,
      'selected_photo_paths': selected,
      'phase': phase,
      'revision': revision,
    }),
  );
  factory _Pending.decode(String encoded) {
    Object? raw;
    try {
      raw = jsonDecode(encoded);
    } catch (_) {
      throw StateError('保留中の写真申請を確認できません。');
    }
    final value = raw;
    const keys = {
      'version',
      'contract',
      'actor_id',
      'company_id',
      'target_id',
      'request_id',
      'expected_photo_paths',
      'selected_photo_paths',
      'phase',
      'revision',
    };
    if (value is! Map ||
        value.length != keys.length ||
        !value.keys.every(keys.contains) ||
        value['version'] is! int ||
        value['version'] != 1 ||
        value['contract'] != 'qualification_admin_saved_photo_pending' ||
        !['actor_id', 'company_id', 'target_id', 'request_id'].every(
          (key) =>
              value[key] is String &&
              AdminSavedQualificationPhotoCapability.isUuid(
                value[key] as String,
              ),
        ) ||
        !_phases.contains(value['phase']) ||
        value['revision'] is! int ||
        value['revision'] < 0 ||
        value['revision'] >= 2147483647 ||
        value['expected_photo_paths'] is! List ||
        value['selected_photo_paths'] is! List) {
      throw StateError('保留中の写真申請の対象を確認できません。');
    }
    final saved = value['expected_photo_paths'] as List,
        selected = value['selected_photo_paths'] as List;
    if (saved.isEmpty ||
        saved.length > 20 ||
        saved.toSet().length != saved.length ||
        saved.any((p) => p is! String || p.trim().isEmpty) ||
        selected.length > 20 ||
        selected.toSet().length != selected.length ||
        selected.any((p) => p is! String || !saved.contains(p))) {
      throw StateError('保留中の写真申請の選択を確認できません。');
    }
    return _Pending._(
      value['actor_id'] as String,
      value['company_id'] as String,
      value['target_id'] as String,
      value['request_id'] as String,
      saved.cast<String>(),
      selected.cast<String>(),
      value['phase'] as String,
      value['revision'] as int,
      encoded,
    );
  }
  _Pending next(String phase) => _Pending.create(
    actorId,
    companyId,
    targetId,
    requestId,
    savedPaths,
    selectedPaths,
    phase,
    revision + 1,
  );
  Map<String, dynamic> get preparePayload => Map.unmodifiable({
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

class _TransportFailure implements Exception {
  const _TransportFailure();
}
