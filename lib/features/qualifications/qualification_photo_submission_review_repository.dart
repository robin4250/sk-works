import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class QualificationReviewUncertain extends StateError {
  QualificationReviewUncertain() : super('結果を確認できません。一覧を更新して同じ申請の状態を確認してください。');
}

class QualificationPhotoSubmissionReviewRepository {
  QualificationPhotoSubmissionReviewRepository(this.client);
  final SupabaseClient client;
  static QualificationPhotoSubmissionReviewRepository? maybeCreate() =>
      SupabaseBackend.isInitialized &&
          SupabaseBackend.client.auth.currentUser != null
      ? QualificationPhotoSubmissionReviewRepository(SupabaseBackend.client)
      : null;

  String get actorId {
    final id = client.auth.currentUser?.id;
    if (id == null) throw StateError('SKOへのログインが必要です。');
    return id;
  }

  void requireActor(String actor) {
    if (client.auth.currentUser?.id != actor)
      throw StateError('ログインが変更されました。画面を開き直してください。');
  }

  Future<dynamic> _call(String action, Map<String, dynamic> data) async {
    final actor = actorId;
    final value = await client.rpc(
      'personal_qualification_submission',
      params: {'p_action': action, 'p_data': data},
    );
    requireActor(actor);
    return value;
  }

  Future<List<Map<String, dynamic>>> pending() async {
    final result = await _call('list', {});
    if (result is! List) {
      throw StateError('資格申請の一覧を確認できません。');
    }
    return result
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .where((row) => row['status'] == 'pending' && row['can_review'] == true)
        .toList();
  }

  static List<String> paths(Map<String, dynamic> row) {
    if (row['photo_contract_version'] == 1 || row['version'] == 1) {
      final raw = row['photo_paths'];
      if (raw is! List ||
          raw.length > 20 ||
          raw.toSet().length != raw.length ||
          raw.any((p) => p is! String || p.trim().isEmpty)) {
        throw StateError('申請写真の情報を確認できません。');
      }
      return raw.cast<String>();
    }
    final path = row['attachment_path'];
    return path is String && path.isNotEmpty ? [path] : [];
  }

  Future<List<String>> photos(Map<String, dynamic> row) async {
    final actor = actorId;
    requireActor(actor);
    if (row['photo_contract_version'] != 1) {
      return paths(row);
    }
    final value = await _call('get_photos', {'id': row['id']});
    if (value is! Map ||
        value['id'] != row['id'] ||
        value['target_id'] != row['target_id'] ||
        value['requested_by'] != row['requested_by'] ||
        value['status'] != 'pending' ||
        value['cancelled'] == true) {
      throw StateError('申請が更新されています。一覧を更新してください。');
    }
    return paths(Map<String, dynamic>.from(value));
  }

  Future<String> signedUrl(String path) async {
    final actor = actorId;
    final value = await client.storage
        .from('qualification-certificates')
        .createSignedUrl(path, 600);
    requireActor(actor);
    return value;
  }

  Future<String?> confirmedStatus(Map<String, dynamic> row) async {
    final value = row['photo_contract_version'] == 1
        ? await _call('get_photos', {'id': row['id']})
        : (await _call('list', {}) as List)
              .whereType<Map>()
              .where((r) => r['id'] == row['id'])
              .firstOrNull;
    if (value is! Map ||
        value['id'] != row['id'] ||
        value['target_id'] != row['target_id'] ||
        value['requested_by'] != row['requested_by']) {
      return null;
    }
    final status = value['status'];
    return ['pending', 'approved', 'rejected'].contains(status)
        ? status as String
        : null;
  }

  Future<void> review(
    Map<String, dynamic> row, {
    required bool approve,
    String? reason,
  }) async {
    final actor = actorId;
    if (row['can_review'] != true || row['status'] != 'pending') {
      throw StateError('承認できる申請ではありません。');
    }
    if (!approve && (reason == null || reason.trim().isEmpty)) {
      throw StateError('却下理由を入力してください。');
    }
    try {
      await _call(approve ? 'approve' : 'reject', {
        'id': row['id'],
        if (!approve) 'reason': reason!.trim(),
      });
    } catch (error) {
      requireActor(actor);
      if (error is PostgrestException &&
          (error.code?.startsWith('P') == true ||
              error.code?.startsWith('23') == true ||
              error.code?.startsWith('42') == true)) {
        rethrow;
      }
      try {
        final status = await confirmedStatus(row);
        requireActor(actor);
        if (status == (approve ? 'approved' : 'rejected')) return;
        if (status == 'pending') {
          throw StateError('申請は承認待ちのままです。内容を確認して再操作できます。');
        }
      } on StateError {
        rethrow;
      } catch (_) {}
      throw QualificationReviewUncertain();
    }
  }
}
