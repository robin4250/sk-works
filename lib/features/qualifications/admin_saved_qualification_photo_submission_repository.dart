import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../shared/trade_document_form_session.dart';
import 'admin_saved_qualification_photo_contract.dart';
import 'admin_saved_qualification_photo_file_journal.dart';

bool _uuid(Object? v) =>
    v is String && AdminSavedQualificationPhotoCapability.isUuid(v);
bool _paths(Object? v) =>
    v is List &&
    v.length <= 20 &&
    v.every((p) => p is String && p.trim().isNotEmpty && p == p.trim()) &&
    v.toSet().length == v.length;

class AdminSavedQualificationTarget {
  AdminSavedQualificationTarget(Map<String, dynamic> row)
    : company = row['company_id'] as String,
      worker = row['worker_id'] as String,
      id = row['id'] as String,
      paths = List.unmodifiable(_readPaths(row)) {
    if (![_uuid(company), _uuid(worker), _uuid(id)].every((v) => v)) {
      throw StateError('資格の会社・本人・対象を確認できません。');
    }
  }
  final String company, worker, id;
  final List<String> paths;
  static List<String> _readPaths(Map<String, dynamic> row) {
    if (!row.containsKey('attachment_path') ||
        !row.containsKey('attachment_back_path') ||
        !row.containsKey('attachment_extra_paths') ||
        row['attachment_extra_paths'] is! List) {
      throw StateError('保存済み写真の全体を確認できません。再読み込みしてください。');
    }
    final values = [
      row['attachment_path'],
      row['attachment_back_path'],
      ...row['attachment_extra_paths'] as List,
    ];
    if (values.any((v) => v != null && (v is! String || v.isEmpty))) {
      throw StateError('保存済み写真の情報を確認できません。');
    }
    final paths = values.whereType<String>().toList();
    if (!_paths(paths)) throw StateError('保存済み写真の情報を確認できません。');
    return paths;
  }
}

abstract interface class AdminSavedQualificationPort {
  String get actor;
  String get sid;
  Future<void> check();
  Future<Object?> call(String action, Map<String, dynamic> data);
  Future<String?> readJournal(String key);
  Future<void> writeJournal(String key, String value);
  Future<void> clearJournal(String key);
}

/// Uses the existing exact SDK-session/gateway lease. No global Auth changes.
class LiveAdminSavedQualificationPort implements AdminSavedQualificationPort {
  LiveAdminSavedQualificationPort(
    this.client,
    this.target, {
    required bool Function() current,
    this.journalDirectory,
  }) {
    final session = client.auth.currentSession;
    final raw = session?.accessToken.split('.');
    if (raw == null || raw.length != 3) throw StateError('現在のログインを確認してください。');
    final claims = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(raw[1]))),
    );
    if (claims is! Map ||
        !_uuid(claims['session_id']) ||
        claims['sub'] != client.auth.currentUser?.id) {
      throw StateError('現在のログインを確認してください。');
    }
    actor = client.auth.currentUser!.id;
    sid = claims['session_id'] as String;
    _token = session!.accessToken;
    lease = TradeDocumentFormSession(
      client,
      target: true,
      currentTarget: current,
    );
    lease.addListener(_retireReads);
  }
  final SupabaseClient client;
  final AdminSavedQualificationTarget target;
  final Future<Directory> Function()? journalDirectory;
  late final _journal = FileAdminSavedQualificationPhotoJournal(
    currentActor: () => client.auth.currentUser?.id,
    requireScope: lease.requireScope,
    directory: journalDirectory,
    legacyRead: (key) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      return prefs.getString(key);
    },
  );
  late final TradeDocumentFormSession lease;
  late final String _token;
  final _retiredReads = Completer<void>();
  void _retireReads() {
    if (!_retiredReads.isCompleted) _retiredReads.complete();
  }

  @override
  late final String actor;
  @override
  late final String sid;
  @override
  Future<void> check() async {
    await lease.ready();
    final counted = await client
        .from('company_members')
        .select('company_id,role')
        .eq('user_id', actor)
        .limit(2)
        .count(CountOption.exact)
        .setHeader('Authorization', 'Bearer $_token')
        .abortSignal(_retiredReads.future)
        .timeout(const Duration(seconds: 30));
    await lease.ready();
    final membership = counted.data;
    // Existing qualification navigation has no verified selected-company bridge.
    // Until it does, multiple memberships are read-only rather than picking first.
    if (counted.count != 1 ||
        membership.length != 1 ||
        membership.single['company_id'] != target.company ||
        !const ['owner', 'admin'].contains(membership.single['role'])) {
      throw StateError('現在の会社の管理権限を確認できません。');
    }
    final workers = await lease.readWorkerCompany(target.worker);
    if (workers is! List ||
        workers.length != 1 ||
        workers.single is! Map ||
        workers.single['id'] != target.worker ||
        workers.single['company_id'] != target.company) {
      throw StateError('資格の会社・社員が変わりました。');
    }
    lease.requireScope();
  }

  @override
  Future<Object?> call(String action, Map<String, dynamic> data) async {
    await check();
    final value = await lease.rpc('personal_qualification_submission', {
      'p_action': action,
      'p_data': data,
    });
    await check();
    return value;
  }

  @override
  Future<String?> readJournal(String key) => _journal.read(key);
  @override
  Future<void> writeJournal(String key, String value) =>
      _journal.write(key, value);
  @override
  Future<void> clearJournal(String key) => _journal.clear(key);
  Future<String> signedSavedPhoto(String path) async {
    await check();
    if (!target.paths.contains(path)) throw StateError('対象外の写真です。');
    final value = await client.storage
        .from('qualification-certificates')
        .createSignedUrl(path, 60);
    await check();
    return value;
  }

  void dispose() {
    _retireReads();
    lease.removeListener(_retireReads);
    lease.dispose();
  }
}

class AdminSavedQualificationResult {
  const AdminSavedQualificationResult(this.status, this.cancelled);
  final String status;
  final bool cancelled;
  static AdminSavedQualificationResult parse(
    Object? raw,
    Map<String, dynamic> journal,
  ) {
    const keys = {
      'version',
      'id',
      'target_id',
      'status',
      'cancelled',
      'reason',
      'requested_by',
      'photo_paths',
      'upload_paths',
    };
    if (raw is! Map ||
        raw.length != keys.length ||
        !raw.keys.every(keys.contains) ||
        raw['version'] is! int ||
        raw['version'] != 1 ||
        raw['id'] != journal['request_id'] ||
        raw['target_id'] != journal['target_id'] ||
        raw['requested_by'] != journal['actor_id'] ||
        raw['cancelled'] is! bool ||
        (raw['reason'] != null && raw['reason'] is! String) ||
        !_paths(raw['photo_paths']) ||
        !listEquals(
          raw['photo_paths'] as List,
          journal['selected_paths'] as List,
        ) ||
        raw['upload_paths'] is! List ||
        (raw['upload_paths'] as List).isNotEmpty ||
        !const [
          'draft',
          'pending',
          'approved',
          'rejected',
        ].contains(raw['status']) ||
        (raw['cancelled'] == true && raw['status'] != 'rejected')) {
      throw StateError('申請結果を確認できません。同じ申請を再確認してください。');
    }
    return AdminSavedQualificationResult(
      raw['status'] as String,
      raw['cancelled'] as bool,
    );
  }
}

/// A fixed intent is persisted BEFORE prepare. Recovery only reads get_photos.
/// Scope in server results is limited to id/target/requester; company/worker/SID
/// are local lease context, not claimed as a server attestation.
class AdminSavedQualificationSubmissionRepository {
  AdminSavedQualificationSubmissionRepository(this.port, this.target);
  final AdminSavedQualificationPort port;
  final AdminSavedQualificationTarget target;
  static final _busy = <String>{};
  String get journalKey =>
      'sko.admin.qualification.saved.v1.${port.actor}.${target.company}.${target.id}';
  Future<T> _exclusive<T>(Future<T> Function() action) async {
    if (!_busy.add(journalKey)) throw StateError('同じ資格の申請を処理中です。');
    try {
      return await action();
    } finally {
      _busy.remove(journalKey);
    }
  }

  Future<AdminSavedQualificationPhotoCapability> capability() async {
    await port.check();
    return AdminSavedQualificationPhotoCapability.parse(
      await port.call('admin_saved_photo_capability', {
        'company_id': target.company,
      }),
      companyId: target.company,
      actorId: port.actor,
    );
  }

  Future<Map<String, dynamic>?> journal() async {
    await port.check();
    final value = await port.readJournal(journalKey);
    if (value == null) return null;
    final raw = jsonDecode(value);
    const keys = {
      'version',
      'actor_id',
      'company_id',
      'worker_id',
      'target_id',
      'session_id',
      'request_id',
      'expected_photo_paths',
      'selected_paths',
      'stage',
    };
    if (raw is! Map ||
        raw.length != keys.length ||
        !raw.keys.every(keys.contains) ||
        raw['version'] is! int ||
        raw['version'] != 1 ||
        raw['actor_id'] != port.actor ||
        raw['company_id'] != target.company ||
        raw['worker_id'] != target.worker ||
        raw['target_id'] != target.id ||
        !_uuid(raw['session_id']) ||
        !_uuid(raw['request_id']) ||
        !_paths(raw['expected_photo_paths']) ||
        !_paths(raw['selected_paths']) ||
        !(raw['selected_paths'] as List).every(
          (p) => (raw['expected_photo_paths'] as List).contains(p),
        ) ||
        !const [
          'prepare_started',
          'prepared',
          'submit_started',
          'pending',
          'approved',
          'rejected',
          'unknown',
        ].contains(raw['stage'])) {
      throw StateError('保存された申請情報を確認できません。再送せず確認してください。');
    }
    return Map<String, dynamic>.from(raw);
  }

  Future<void> _save(Map<String, dynamic> journal) async {
    await port.check();
    await port.writeJournal(journalKey, jsonEncode(journal));
    await port.check();
  }

  String _requestId() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final s = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
  }

  Future<AdminSavedQualificationResult> submit(
    List<String> selected,
  ) => _exclusive(() async {
    await port.check();
    if (await journal() != null) throw StateError('既存の申請を再確認してください。再送はできません。');
    if (!_paths(selected) ||
        !selected.every(target.paths.contains) ||
        target.paths.isEmpty) {
      throw StateError('保存済み写真だけを選択してください。');
    }
    final cap = await capability();
    if (!cap.available) throw StateError('管理者の資格写真申請は準備中です。');
    final record = <String, dynamic>{
      'version': 1,
      'actor_id': port.actor,
      'company_id': target.company,
      'worker_id': target.worker,
      'target_id': target.id,
      'session_id': port.sid,
      'request_id': _requestId(),
      'expected_photo_paths': target.paths,
      'selected_paths': List<String>.of(selected),
      'stage': 'prepare_started',
    };
    await _save(record);
    try {
      final prepared = AdminSavedQualificationResult.parse(
        await port.call('prepare_admin_saved_photos', {
          'company_id': target.company,
          'target_id': target.id,
          'request_id': record['request_id'],
          'expected_photo_paths': target.paths,
          'photo_slots': [
            for (final path in selected) {'existing_path': path},
          ],
        }),
        record,
      );
      if (prepared.status != 'draft' || prepared.cancelled) {
        throw StateError('新規申請の下書き状態を確認できません。');
      }
      record['stage'] = 'prepared';
      await _save(record);
      record['stage'] = 'submit_started';
      await _save(record);
      await port.call('submit', {'id': record['request_id']});
      final saved = AdminSavedQualificationResult.parse(
        await port.call('get_photos', {'id': record['request_id']}),
        record,
      );
      if (saved.status != 'pending' && saved.status != 'approved') {
        throw StateError('申請受付の状態を確認できません。');
      }
      record['stage'] = saved.status;
      await _save(record);
      return saved;
    } catch (_) {
      // Never repeat a mutation even if a denial is returned after dispatch.
      // Original journal remains usable after scope retirement or process exit.
      rethrow;
    }
  });

  /// Explicit acknowledgement only after an authoritative final result.
  /// Preserve an immutable local copy before clearing the active pointer.
  Future<void> acknowledgeFinal() => _exclusive(() async {
    final record = await journal();
    if (record == null) return;
    final result = AdminSavedQualificationResult.parse(
      await port.call('get_photos', {'id': record['request_id']}),
      record,
    );
    if (result.status != 'approved' && result.status != 'rejected') {
      throw StateError('未解決・承認待ちの申請は残します。');
    }
    record['stage'] = result.status;
    final archiveKey = '$journalKey.receipt.${record['request_id']}';
    final encoded = jsonEncode(record);
    final existing = await port.readJournal(archiveKey);
    if (existing != null && existing != encoded) {
      throw StateError('保存済み申請結果が一致しません。');
    }
    if (existing == null) await port.writeJournal(archiveKey, encoded);
    await port.check();
    await port.clearJournal(journalKey);
    await port.check();
  });
  Future<AdminSavedQualificationResult?> reconcile() => _exclusive(() async {
    final record = await journal();
    if (record == null) return null;
    final result = AdminSavedQualificationResult.parse(
      await port.call('get_photos', {'id': record['request_id']}),
      record,
    );
    record['stage'] = result.status == 'draft' ? 'prepared' : result.status;
    await _save(record);
    return result;
  });
}
