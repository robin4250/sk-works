import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../shared/trade_document_form_session.dart';

/// Separate purpose from employee requests; never approves a personal request.
/// The durable journal contains only operation IDs, never a command or snapshot.
class WorkerDocumentAdminCorrectionRepository {
  WorkerDocumentAdminCorrectionRepository.forTesting({
    required this.actor,
    required this.companyId,
    required this.targetId,
    required this.preferences,
    required Future<Object?> Function(String, Map<String, dynamic>) rpc,
    required void Function() requireCurrent,
    void Function()? dispose,
  }) : _rpc = rpc,
       _requireCurrent = requireCurrent,
       _dispose = dispose;

  factory WorkerDocumentAdminCorrectionRepository({
    required SupabaseClient client,
    required String companyId,
    required String targetId,
    required SharedPreferences preferences,
    required bool Function() isCurrentTarget,
  }) {
    final actor = client.auth.currentUser?.id;
    if (actor == null) {
      throw StateError('ログイン状態を確認してください。');
    }
    final session = TradeDocumentFormSession(
      client,
      target: true,
      currentTarget: isCurrentTarget,
    );
    return WorkerDocumentAdminCorrectionRepository.forTesting(
      actor: actor,
      companyId: companyId,
      targetId: targetId,
      preferences: preferences,
      rpc: (action, data) => session.rpc(
        'worker_document_admin_self_correction',
        {'p_action': action, 'p_data': data},
      ),
      // ready() in the captured-session transport handles initial admission.
      requireCurrent: () {
        if (client.auth.currentUser?.id != actor || !isCurrentTarget()) {
          throw StateError('ログイン・会社・書類の状態が変わりました。');
        }
      },
      dispose: session.dispose,
    );
  }

  final String actor, companyId, targetId;
  final SharedPreferences preferences;
  final Future<Object?> Function(String, Map<String, dynamic>) _rpc;
  final void Function() _requireCurrent;
  final void Function()? _dispose;
  bool _busy = false, _disposed = false;
  static final _busyTargets = <String>{};
  static List<String> pendingTargets(
    SharedPreferences preferences,
    String actor,
    String companyId,
  ) {
    final prefix = 'sko.document.admin.correction.v1:$actor:$companyId:';
    final targets = <String>[];
    for (final key in preferences.getKeys().where(
      (key) => key.startsWith(prefix),
    )) {
      final target = key.substring(prefix.length);
      final raw = jsonDecode(preferences.getString(key) ?? 'null');
      if (!RegExp(r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')
              .hasMatch(target) ||
          raw is! Map ||
          raw.length != 5 ||
          raw['version'] != 1 ||
          raw['actor_id'] != actor ||
          raw['company_id'] != companyId ||
          raw['target_id'] != target ||
          raw['request_id'] is! String) {
        throw const FormatException('保存された変更IDを確認できません。');
      }
      targets.add(target);
    }
    return targets..sort();
  }

  String get _key =>
      'sko.document.admin.correction.v1:$actor:$companyId:$targetId';
  Map<String, dynamic> get _target => {
    'company_id': companyId,
    'target_id': targetId,
  };

  void _current() {
    if (_disposed) {
      throw StateError('変更画面を開き直してください。');
    }
    _requireCurrent();
  }

  Map<String, dynamic> _identity(String requestId) => {
    'version': 1,
    'actor_id': actor,
    'company_id': companyId,
    'target_id': targetId,
    'request_id': requestId,
  };

  String? pendingRequest() {
    _current();
    final value = preferences.getString(_key);
    if (value == null) {
      return null;
    }
    final raw = jsonDecode(value);
    if (raw is! Map ||
        raw.length != 5 ||
        raw['request_id'] is! String ||
        jsonEncode(raw) != jsonEncode(_identity(raw['request_id'] as String))) {
      throw const FormatException('保存された変更IDを確認できません。');
    }
    return raw['request_id'] as String;
  }

  Future<bool> available() async {
    _current();
    final raw = await _rpc('capability', _target);
    _current();
    if (raw is! Map ||
        raw.length != 8 ||
        raw['version'] is! int ||
        raw['version'] != 1 ||
        raw['contract'] != 'worker_document_admin_self_correction' ||
        raw['company_id'] != companyId ||
        raw['target_id'] != targetId ||
        raw['actor_id'] != actor ||
        raw['available'] is! bool ||
        raw['new_upload_available'] != false ||
        raw['max_photos'] is! int ||
        raw['max_photos'] != 20) {
      throw const FormatException('管理訂正の利用状態を照合できません。');
    }
    return raw['available'] as bool;
  }

  String _receipt(Object? raw, String requestId) {
    if (raw is! Map ||
        raw.length != 7 ||
        raw['version'] != 1 ||
        raw['contract'] != 'worker_document_admin_self_correction' ||
        raw['request_id'] != requestId ||
        raw['company_id'] != companyId ||
        raw['target_id'] != targetId ||
        raw['actor_id'] != actor ||
        !['applied', 'cancelled', 'unknown'].contains(raw['status'])) {
      throw const FormatException('変更結果を照合できません。');
    }
    return raw['status'] as String;
  }

  /// Existing list projections omit updated_by/template_version_id. Only this
  /// authorized server snapshot may be used for the full-row CAS command.
  Future<Map<String, dynamic>> inspect() async {
    _current();
    final raw = await _rpc('inspect', _target);
    _current();
    if (raw is! Map ||
        raw.length != 6 ||
        raw['version'] is! int ||
        raw['version'] != 1 ||
        raw['contract'] != 'worker_document_admin_self_correction' ||
        raw['company_id'] != companyId ||
        raw['target_id'] != targetId ||
        raw['actor_id'] != actor ||
        raw['snapshot'] is! Map) {
      throw const FormatException('正式な書類状態を照合できません。');
    }
    final snapshot = Map<String, dynamic>.from(raw['snapshot'] as Map);
    if (snapshot['id'] != targetId ||
        snapshot['company_id'] != companyId ||
        snapshot['worker_id'] is! String ||
        snapshot['requirement_id'] is! String ||
        snapshot['updated_at'] is! String ||
        !snapshot.containsKey('updated_by') ||
        !snapshot.containsKey('template_version_id')) {
      throw const FormatException('正式な書類状態が不足しています。');
    }
    return jsonDecode(jsonEncode(snapshot)) as Map<String, dynamic>;
  }

  Future<void> _clear(String requestId) async {
    _current();
    if (pendingRequest() != requestId || !await preferences.remove(_key)) {
      throw StateError('変更結果の端末保存を確認できません。');
    }
    _current();
    if (preferences.getString(_key) != null) {
      throw StateError('変更IDの解除を確認できません。');
    }
  }

  Future<T> _exclusive<T>(Future<T> Function() action) async {
    _current();
    if (_busy || !_busyTargets.add(_key)) {
      throw StateError('変更結果を確認中です。');
    }
    _busy = true;
    try {
      return await action();
    } finally {
      _busy = false;
      _busyTargets.remove(_key);
    }
  }

  /// Caller supplies one secure UUID and the reviewed full snapshot. No retries
  /// resend the command: on uncertainty recover() fences/reconciles this ID.
  Future<String> correct({
    required String requestId,
    required Map<String, dynamic> expectedSnapshot,
    required List<String> paths,
    required String? expiresAt,
    required String? notes,
    required String reason,
  }) => _exclusive(() async {
    if (pendingRequest() != null) {
      throw StateError('前の変更結果を先に確認してください。');
    }
    if (!RegExp(r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')
            .hasMatch(requestId) ||
        expectedSnapshot['id'] != targetId ||
        expectedSnapshot['company_id'] != companyId ||
        !expectedSnapshot.containsKey('updated_by') ||
        !expectedSnapshot.containsKey('template_version_id') ||
        reason.trim().isEmpty ||
        reason != reason.trim() ||
        reason.length > 1000) {
      throw const FormatException('変更対象と理由を確認してください。');
    }
    // Freeze in memory before any await; never serialize this into preferences.
    final command = jsonDecode(
      jsonEncode({
        ..._target,
        'request_id': requestId,
        'expected_snapshot': expectedSnapshot,
        'fields': {
          'attachment_paths': paths,
          'expires_at': expiresAt,
          'notes': notes,
        },
        'reason': reason,
      }),
    ) as Map<String, dynamic>;
    final identity = jsonEncode(_identity(requestId));
    if (!await preferences.setString(_key, identity) ||
        preferences.getString(_key) != identity) {
      throw StateError('変更IDを保存できません。送信していません。');
    }
    _current();
    final raw = await _rpc('correct', command);
    _current();
    final status = _receipt(raw, requestId);
    if (status == 'applied' || status == 'cancelled') {
      await _clear(requestId);
    }
    return status;
  });

  /// An absent receipt alone is not evidence of rollback. The cancellation RPC
  /// shares the write lock and records a tombstone before a new command is safe.
  Future<String?> recover() => _exclusive(() async {
    final requestId = pendingRequest();
    if (requestId == null) {
      return null;
    }
    final raw = await _rpc('reconcile_cancel', {
      ..._target,
      'request_id': requestId,
    });
    _current();
    final status = _receipt(raw, requestId);
    if (status == 'applied' || status == 'cancelled') {
      await _clear(requestId);
    }
    return status;
  });

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _dispose?.call();
  }
}
