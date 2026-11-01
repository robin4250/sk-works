import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/app_auth_mutation_gateway.dart';

/// A read-only lifetime bound to one existing SDK session and one membership.
/// This does not adopt Auth, create a worker or grant server-side authority.
class QualificationDocumentReadScope {
  QualificationDocumentReadScope._(this.client, this._session, this.actor,
      this.token, this.sid, this._gateway, this._epoch);
  final SupabaseClient client;
  final Session _session;
  final String actor;
  final String token;
  final String sid;
  final AppAuthMutationGateway _gateway;
  final int _epoch;
  late final String companyId;
  late final String role;
  bool _retired = false;

  static bool uuid(Object? value) => value is String && RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false).hasMatch(value);

  static String? _sessionId(Session? session, String? actor) {
    if (session == null || !uuid(actor) || session.accessToken.length > 16384) return null;
    try {
      final parts = session.accessToken.split('.');
      if (parts.length != 3 || parts.any((part) => part.isEmpty)) return null;
      final raw = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      if (raw is! Map || raw['sub'] != actor || !uuid(raw['session_id']) ||
          raw['exp'] is! int || raw['exp'] <= DateTime.now().millisecondsSinceEpoch ~/ 1000) return null;
      return raw['session_id'] as String;
    } catch (_) { return null; }
  }

  static Future<QualificationDocumentReadScope> capture(SupabaseClient client) async {
    final session = client.auth.currentSession;
    final actor = client.auth.currentUser?.id;
    final sid = _sessionId(session, actor);
    final gateway = AppAuthMutationGateway.forClient(client);
    final epoch = await gateway.externalFlowAdmission();
    if (session == null || !uuid(actor) || sid == null || session.isExpired || epoch == null ||
        !identical(session, client.auth.currentSession)) {
      throw StateError('本人の資格書類を確認できません。');
    }
    final scope = QualificationDocumentReadScope._(
        client, session, actor!, session.accessToken, sid, gateway, epoch);
    final member = await scope._membership();
    scope.companyId = member.companyId;
    scope.role = member.role;
    return scope;
  }

  void check() {
    if (_retired || _session.isExpired ||
        !identical(_session, client.auth.currentSession) ||
        client.auth.currentUser?.id != actor || _sessionId(client.auth.currentSession, actor) != sid ||
        !_gateway.isExternalFlowCurrent(_epoch)) {
      _retired = true;
      throw StateError('ログイン・所属会社の状態が変わりました。再読み込みしてください。');
    }
  }

  Future<T> read<T>(Future<T> Function() operation) async {
    check();
    try {
      final value = await operation();
      check();
      return value;
    } catch (_) {
      check();
      rethrow;
    }
  }

  Future<({String companyId, String role})> _membership() async {
    final rows = await read(() => client.from('company_members')
        .select('company_id, role').eq('user_id', actor).limit(2)
        .setHeader('Authorization', 'Bearer $token'));
    if (rows.length != 1 || !uuid(rows.single['company_id']) ||
        !const ['owner', 'admin', 'manager', 'viewer'].contains(rows.single['role'])) {
      _retired = true;
      throw StateError('所属会社と権限を一意に確認できません。');
    }
    return (companyId: rows.single['company_id'] as String,
        role: rows.single['role'] as String);
  }

  Future<bool> peoplePermission() async {
    final raw = await read(() => client.rpc('current_feature_permissions')
        .setHeader('Authorization', 'Bearer $token'));
    if (raw is! Map || raw['can_manage_people'] is! bool) {
      _retired = true;
      throw StateError('資格書類の閲覧権限を確認できません。');
    }
    return raw['can_manage_people'] as bool;
  }

  Future<Map<String, dynamic>> ownWorker() async {
    final rows = await read(() => client.from('workers')
        .select('id, company_id, user_id, name, affiliation, status')
        .eq('company_id', companyId).eq('user_id', actor)
        .inFilter('status', ['active', 'inactive']).limit(2)
        .setHeader('Authorization', 'Bearer $token'));
    if (rows.length != 1 || !uuid(rows.single['id']) ||
        rows.single['company_id'] != companyId || rows.single['user_id'] != actor ||
        !const ['active', 'inactive'].contains(rows.single['status'])) {
      _retired = true;
      throw StateError('本人の保存済み資格書類を確認できません。');
    }
    return Map<String, dynamic>.from(rows.single);
  }

  Future<Map<String, dynamic>> visibleWorker(String workerId) async {
    if (!uuid(workerId)) throw StateError('対象社員を確認できません。');
    final rows = List<Map<String, dynamic>>.from(await read(() => client.from('workers')
        .select('id, company_id, name, affiliation, status')
        .eq('company_id', companyId).eq('id', workerId).limit(2)
        .setHeader('Authorization', 'Bearer $token')));
    validateWorkers(rows);
    if (rows.length != 1 || rows.single['id'] != workerId) {
      throw StateError('対象社員を一意に確認できません。');
    }
    return rows.single;
  }

  Future<void> verify({Map<String, dynamic>? worker, bool? peoplePermission}) async {
    final member = await _membership();
    if (member.companyId != companyId || member.role != role) {
      _retired = true;
      throw StateError('所属会社または権限が変更されました。');
    }
    if (worker != null) {
      final fresh = await ownWorker();
      if (fresh['id'] != worker['id'] || fresh['status'] != worker['status']) {
        _retired = true;
        throw StateError('本人の在籍状態が変更されました。');
      }
    }
    if (peoplePermission != null && await this.peoplePermission() != peoplePermission) {
      _retired = true;
      throw StateError('資格書類の閲覧権限が変更されました。');
    }
    final last = await _membership();
    if (last.companyId != companyId || last.role != role) {
      _retired = true;
      throw StateError('所属会社または権限が変更されました。');
    }
    check();
  }

  void validateWorkers(List<Map<String, dynamic>> rows) {
    if (rows.any((row) => !uuid(row['id']) || row['company_id'] != companyId ||
        !const ['active', 'inactive'].contains(row['status'])) ||
        rows.map((row) => row['id']).toSet().length != rows.length) {
      throw StateError('対象の社員情報を確認できません。');
    }
  }

  void validateQualifications(List<Map<String, dynamic>> rows, {String? ownWorkerId}) {
    if (rows.any((row) => !uuid(row['id']) || !uuid(row['worker_id']) ||
        !uuid(row['qualification_master_id']) || row['company_id'] != companyId ||
        (ownWorkerId != null && row['worker_id'] != ownWorkerId)) ||
        rows.map((row) => row['id']).toSet().length != rows.length) {
      throw StateError('保存済み資格書類を照合できません。');
    }
  }

  static bool missingPhotoColumn(PostgrestException error, String column) =>
      const ['42703', 'PGRST204'].contains(error.code) &&
      RegExp('(?<![A-Za-z0-9_])${RegExp.escape(column)}(?![A-Za-z0-9_])')
          .hasMatch(error.message);

  Future<List<Map<String, dynamic>>> photoRows({String? workerId, String? qualificationId}) async {
    if ((workerId != null && !uuid(workerId)) ||
        (qualificationId != null && !uuid(qualificationId))) {
      throw StateError('資格書類の識別情報を確認できません。');
    }
    final optional = <String>{'attachment_back_path', 'attachment_extra_paths'};
    for (;;) {
      try {
        final rows = await read(() {
          var query = client.from('worker_qualifications')
              .select(['id', 'company_id', 'worker_id', 'qualification_master_id',
                'attachment_path', ...optional].join(', '))
              .eq('company_id', companyId);
          if (workerId != null) query = query.eq('worker_id', workerId);
          if (qualificationId != null) query = query.eq('id', qualificationId);
          return query.setHeader('Authorization', 'Bearer $token');
        });
        final values = List<Map<String, dynamic>>.from(rows);
        validateQualifications(values, ownWorkerId: workerId);
        return values;
      } on PostgrestException catch (error) {
        check();
        final missing = optional.where((field) => missingPhotoColumn(error, field)).toList();
        if (missing.length != 1) rethrow;
        optional.remove(missing.single);
      }
    }
  }

  static List<String> photoPaths(Map<String, dynamic> row) {
    final extra = row['attachment_extra_paths'];
    if (extra != null && extra is! List) throw StateError('資格証写真を確認できません。');
    final values = [row['attachment_path'], row['attachment_back_path'],
      if (extra is List) ...extra];
    if (values.any((value) => value != null &&
        (value is! String || value.trim().isEmpty))) {
      throw StateError('資格証写真を確認できません。');
    }
    return values.whereType<String>().toSet().toList();
  }

  void validatePhotoPath(String path, Map<String, dynamic> row) {
    final parts = path.split('/');
    if (!photoPaths(row).contains(path) || parts.length < 3 || parts.length > 5 ||
        parts[0] != companyId || parts[1] != row['worker_id'] ||
        (parts.length >= 4 && parts[2] != row['id']) ||
        parts.any((part) => part.isEmpty || part == '.' || part == '..' ||
            RegExp(r'[\\%?#:\x00-\x1f]').hasMatch(part))) {
      throw StateError('保存済み資格証写真の場所を確認できません。');
    }
  }

  Future<String> signPhoto(String path, Map<String, dynamic> row) async {
    validatePhotoPath(path, row);
    return read(() => client.storage.from('qualification-certificates')
        .setHeader('Authorization', 'Bearer $token').createSignedUrl(path, 60 * 10));
  }
}
