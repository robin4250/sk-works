import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import '../people/worker_document_photos.dart';
import 'own_qualification_photo_contract.dart';
import 'own_qualification_photo_selection.dart';
import 'qualification_cloud_repository.dart';

class OwnQualificationPhotoSubmissionRepository {
  OwnQualificationPhotoSubmissionRepository._(this._client);
  OwnQualificationPhotoSubmissionRepository.forTesting({
    required String? Function() actor,
    required Future<({String userId, String companyId, String workerId})>
    Function()
    scope,
    required Future<Object?> Function(String action, Map<String, dynamic> data)
    rpc,
    required Future<void> Function(
      String path,
      Uint8List bytes,
      FileOptions options,
    )
    upload,
  }) : _client = null,
       _actorOverride = actor,
       _scopeOverride = scope,
       _rpcOverride = rpc,
       _uploadOverride = upload;
  final SupabaseClient? _client;
  String? Function()? _actorOverride;
  Future<({String userId, String companyId, String workerId})> Function()?
  _scopeOverride;
  Future<Object?> Function(String action, Map<String, dynamic> data)?
  _rpcOverride;
  Future<void> Function(String path, Uint8List bytes, FileOptions options)?
  _uploadOverride;
  bool _commandBusy = false;
  Future<OwnQualificationPreparedPhotos> _exclusive(
    Future<OwnQualificationPreparedPhotos> Function() action,
  ) async {
    if (_commandBusy) throw StateError('写真申請の処理中です。');
    _commandBusy = true;
    try {
      return await action();
    } finally {
      _commandBusy = false;
    }
  }

  static OwnQualificationPhotoSubmissionRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized ||
        SupabaseBackend.client.auth.currentUser == null) {
      return null;
    }
    return OwnQualificationPhotoSubmissionRepository._(SupabaseBackend.client);
  }

  String? get actor => _actorOverride != null
      ? _actorOverride!()
      : _client!.auth.currentUser?.id;

  void _check(String userId) {
    if (actor != userId) throw StateError('ログイン状態が変わりました。画面を開き直してください。');
  }

  Future<Object?> _rpc(
    String userId,
    String action,
    Map<String, dynamic> data,
  ) async {
    _check(userId);
    final value = _rpcOverride != null
        ? await _rpcOverride!(action, data)
        : await _client!.rpc(
            'personal_qualification_submission',
            params: {'p_action': action, 'p_data': data},
          );
    _check(userId);
    return value;
  }

  Future<OwnQualificationPhotoCapability> capability() async {
    final userId = actor;
    if (userId == null) return OwnQualificationPhotoCapability.unavailable;
    try {
      return OwnQualificationPhotoCapability.parse(
        await _rpc(userId, 'photo_capability', {}),
      );
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST202' ||
          error.code == '42883' ||
          (error.code == 'P0001' && error.message == '申請が見つかりません')) {
        return OwnQualificationPhotoCapability.unavailable;
      }
      rethrow;
    }
  }

  Future<({String userId, String companyId, String workerId})> _scope() async {
    final userId = actor;
    if (_scopeOverride != null) {
      final scope = await _scopeOverride!();
      _check(scope.userId);
      return scope;
    }
    final cloud = QualificationCloudRepository.maybeCreate();
    if (userId == null || cloud == null) throw StateError('ログインを確認してください。');
    final membership = await cloud.membership();
    _check(userId);
    final worker = await cloud.currentWorker();
    _check(userId);
    return (
      userId: userId,
      companyId: membership.companyId,
      workerId: worker.workerId,
    );
  }

  String _key(String userId, String companyId) =>
      'sko.own.qualification.photos.pending.v1.$userId.$companyId';
  Future<void> _write(Map<String, dynamic> command) async {
    final userId = command['user_id'] as String;
    _check(userId);
    final prefs = await SharedPreferences.getInstance();
    _check(userId);
    if (!await prefs.setString(
      _key(userId, command['company_id'] as String),
      jsonEncode(command),
    )) {
      throw StateError('再確認用の申請情報を保存できませんでした。');
    }
    _check(userId);
  }

  Future<Map<String, dynamic>?> pending() async {
    final scope = await _scope();
    final prefs = await SharedPreferences.getInstance();
    _check(scope.userId);
    final value = prefs.getString(_key(scope.userId, scope.companyId));
    if (value == null) return null;
    final decoded = jsonDecode(value);
    if (decoded is! Map ||
        decoded['version'] != 1 ||
        decoded['user_id'] != scope.userId ||
        decoded['company_id'] != scope.companyId ||
        decoded['worker_id'] != scope.workerId ||
        decoded['request_id'] is! String ||
        decoded['target_id'] is! String ||
        decoded['photo_slots'] is! List) {
      throw StateError('保留中の写真申請の本人を確認できませんでした。');
    }
    return Map<String, dynamic>.from(decoded);
  }

  OwnQualificationPreparedPhotos _parse(
    Object? raw,
    Map<String, dynamic> command,
  ) => OwnQualificationPreparedPhotos.parse(
    raw,
    requestId: command['request_id'] as String,
    userId: command['user_id'] as String,
    targetId: command['target_id'] as String,
    companyId: command['company_id'] as String,
    workerId: command['worker_id'] as String,
    slots: List<Map<String, dynamic>>.from(command['photo_slots'] as List),
  );
  Map<String, dynamic> _preparePayload(Map<String, dynamic> command) => {
    'request_id': command['request_id'],
    'target_id': command['target_id'],
    'photo_slots': command['photo_slots'],
  };

  Future<OwnQualificationPreparedPhotos> submitSelection({
    required Map<String, dynamic> row,
    required List<WorkerDocumentPhoto> photos,
  }) => _exclusive(() => _submitSelection(row: row, photos: photos));

  Future<OwnQualificationPreparedPhotos> _submitSelection({
    required Map<String, dynamic> row,
    required List<WorkerDocumentPhoto> photos,
  }) async {
    final scope = await _scope();
    if (row['worker_id'] != scope.workerId || row['id'] is! String) {
      throw StateError('本人の資格を確認できませんでした。');
    }
    final cap = await capability();
    _check(scope.userId);
    if (!cap.available) throw StateError('資格証写真の申請は準備中です。');
    final selected = validateOwnQualificationPhotoSelection(
      photos: photos,
      savedPaths: QualificationCloudRepository.ownPhotoAttachments(row)
          .map((photo) => photo.path),
    );
    if (selected.length > cap.maxPhotos) throw StateError('写真の選択枚数を減らしてください。');
    if (!cap.uploadAllowed && selected.any((photo) => photo.bytes != null)) {
      throw StateError('新しい資格証写真の送信は停止中です。');
    }
    if (await pending() != null) throw StateError('先に保留中の写真申請を再確認してください。');
    _check(scope.userId);
    final slots = <Map<String, dynamic>>[
      for (final photo in selected)
        if (photo.path != null)
          {'existing_path': photo.path}
        else
          {'extension': _extension(photo.filename!)},
    ];
    final command = <String, dynamic>{
      'version': 1,
      'user_id': scope.userId,
      'company_id': scope.companyId,
      'worker_id': scope.workerId,
      'request_id': _uuid(),
      'target_id': row['id'],
      'photo_slots': slots,
      'attempted_uploads': <int>[],
      'stage': 'prepare',
    };
    // Persist the fixed request before prepare so a lost response never creates
    // a different server draft on retry.
    await _write(command);
    Object? prepareResponse;
    try {
      prepareResponse = await _rpc(
        scope.userId,
        'prepare_photos',
        _preparePayload(command),
      );
    } on PostgrestException catch (error) {
      // A definite server transaction rejection of this first attempt cannot
      // have saved the newly generated request. Transport uncertainty and all
      // recovery attempts retain the original identity instead.
      if (const ['P0001', '42501', '23514', '22023'].contains(error.code)) {
        await _clearPending(command);
      }
      rethrow;
    }
    final prepared = _parse(prepareResponse, command);
    command['stage'] = 'upload';
    await _write(command);
    for (final entry in prepared.uploads.entries) {
      final photo = selected[entry.key];
      if (photo.bytes == null) throw StateError('選択した写真を確認できません。');
      final attempted = List<int>.from(command['attempted_uploads'] as List)
        ..add(entry.key);
      command['attempted_uploads'] = attempted;
      // Record the attempt before Storage writes. Recovery never reuploads an
      // uncertain object; it checks this same request through the server.
      await _write(command);
      final options = FileOptions(
        upsert: false,
        contentType: entry.value.extension == 'png'
            ? 'image/png'
            : entry.value.extension == 'heic'
            ? 'image/heic'
            : entry.value.extension == 'heif'
            ? 'image/heif'
            : 'image/jpeg',
      );
      _check(scope.userId);
      if (_uploadOverride != null) {
        await _uploadOverride!(entry.value.path, photo.bytes!, options);
      } else {
        await _client!.storage
            .from('qualification-certificates')
            .uploadBinary(entry.value.path, photo.bytes!, fileOptions: options);
      }
      _check(scope.userId);
    }
    command['stage'] = 'submit';
    await _write(command);
    return _submitSame(command);
  }

  Future<OwnQualificationPreparedPhotos> _submitSame(
    Map<String, dynamic> command,
  ) async {
    final userId = command['user_id'] as String;
    Object? submitError;
    try {
      await _rpc(userId, 'submit', {'id': command['request_id']});
    } catch (error) {
      submitError = error;
    }
    final saved = _parse(
      await _rpc(userId, 'get_photos', {'id': command['request_id']}),
      command,
    );
    if (saved.status != 'pending' && saved.status != 'approved') {
      throw StateError(
        submitError == null
            ? '写真申請を確定できませんでした。同じ申請を再確認してください。'
            : '写真申請の結果を確認できませんでした。写真を再送せず同じ申請を再確認してください。',
      );
    }
    await _clearPending(command);
    return saved;
  }

  Future<void> _clearPending(Map<String, dynamic> command) async {
    final userId = command['user_id'] as String;
    final prefs = await SharedPreferences.getInstance();
    _check(userId);
    if (!await prefs.remove(_key(userId, command['company_id'] as String))) {
      throw StateError('申請結果は保存されました。保留表示を再確認してください。');
    }
    _check(userId);
  }

  void _checkExpectedRequest(
    Map<String, dynamic> command,
    String? expectedRequestId,
  ) {
    if (expectedRequestId != null &&
        command['request_id'] != expectedRequestId) {
      throw StateError('表示中の写真申請が変わりました。画面を再読み込みしてください。');
    }
  }

  Future<OwnQualificationPreparedPhotos> cancelDraft({
    String? expectedRequestId,
  }) => _exclusive(() async {
    final command = await pending();
    if (command == null) throw StateError('保留中の写真申請はありません。');
    _checkExpectedRequest(command, expectedRequestId);
    return _cancelCommand(command);
  });

  Future<OwnQualificationPreparedPhotos> _cancelCommand(
    Map<String, dynamic> command,
  ) async {
    final userId = command['user_id'] as String;
    // Fix the original identity if prepare's response was lost. This repeats no
    // photo upload and cannot create a different request.
    if (command['stage'] == 'prepare') {
      _parse(
        await _rpc(userId, 'prepare_photos', _preparePayload(command)),
        command,
      );
    }
    final before = _parse(
      await _rpc(userId, 'get_photos', {'id': command['request_id']}),
      command,
    );
    if (before.status == 'rejected' && before.cancelled) {
      await _clearPending(command);
      return before;
    }
    if (before.status != 'draft') {
      throw StateError('下書き以外の写真申請は取り消せません。同じ申請を再確認してください。');
    }
    command['stage'] = 'cancel';
    await _write(command);
    await _rpc(userId, 'cancel_photos', {'id': command['request_id']});
    final saved = _parse(
      await _rpc(userId, 'get_photos', {'id': command['request_id']}),
      command,
    );
    if (saved.status != 'rejected' || !saved.cancelled) {
      throw StateError('写真申請の取消結果を確認できません。同じ申請を再確認してください。');
    }
    await _clearPending(command);
    return saved;
  }

  Future<OwnQualificationPreparedPhotos> recover({String? expectedRequestId}) =>
      _exclusive(() => _recover(expectedRequestId));
  Future<OwnQualificationPreparedPhotos> _recover(
    String? expectedRequestId,
  ) async {
    final command = await pending();
    if (command == null) throw StateError('保留中の写真申請はありません。');
    _checkExpectedRequest(command, expectedRequestId);
    final userId = command['user_id'] as String;
    if (command['stage'] == 'cancel') return _cancelCommand(command);
    // Repeating prepare is safe only for the original fixed command and does
    // not upload bytes. The RPC returns its existing request identity.
    if (command['stage'] == 'prepare') {
      _parse(
        await _rpc(userId, 'prepare_photos', _preparePayload(command)),
        command,
      );
    } else {
      final known = _parse(
        await _rpc(userId, 'get_photos', {'id': command['request_id']}),
        command,
      );
      if (const ['pending', 'approved', 'rejected'].contains(known.status)) {
        await _clearPending(command);
        return known;
      }
    }
    return _submitSame(command);
  }

  Future<List<Map<String, dynamic>>> submissions() async {
    final userId = actor;
    if (userId == null) return const [];
    final value = await _rpc(userId, 'list', {});
    if (value is! List) throw StateError('資格証写真の申請一覧を確認できませんでした。');
    return value
        .whereType<Map>()
        .where(
          (row) =>
              row['requested_by'] == userId &&
              row['photo_contract_version'] == 1,
        )
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  String _extension(String name) {
    final extension = name.split('.').last.toLowerCase();
    if (!const ['jpg', 'jpeg', 'png', 'heic', 'heif'].contains(extension)) {
      throw StateError('JPEG・PNG・HEIC形式の写真を選択してください。');
    }
    return extension;
  }

  String _uuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final value = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${value.substring(0, 8)}-${value.substring(8, 12)}-${value.substring(12, 16)}-${value.substring(16, 20)}-${value.substring(20)}';
  }
}
