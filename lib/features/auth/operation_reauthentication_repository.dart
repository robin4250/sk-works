import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import 'secondary_reset_session_guard.dart';

/// Operation proofs are held in memory only and never stand in for a session.
class OperationReauthenticationRepository {
  OperationReauthenticationRepository(this._client);
  final SupabaseClient _client;

  static OperationReauthenticationRepository? maybeCreate() =>
      SupabaseBackend.isInitialized && SupabaseBackend.client.auth.currentUser != null
          ? OperationReauthenticationRepository(SupabaseBackend.client)
          : null;

  Future<Map<String, bool>> capabilities() async {
    dynamic raw;
    try {
      raw = await _client.rpc('reauthentication_capabilities');
    } on PostgrestException catch (error) {
      // Only a server without the new API keeps its old, documented behavior.
      // Permission, network, schema and other failures must never downgrade.
      if (error.code != 'PGRST202') rethrow;
      return const {'secondary_password': false, 'master_feature': false,
        'master_security': false, 'attendance_management': false,
        'secondary_password_change_supported': false,
        'secondary_password_recovery_supported': false};
    }
    if (raw is! Map || raw['protocol'] != 'sko-reauthentication-v1' ||
        ['secondary_password', 'master_feature', 'master_security']
            .any((key) => raw[key] is! bool)) {
      throw StateError('本人確認の設定を確認できませんでした。');
    }
    const optional = ['attendance_management', 'secondary_password_change_supported',
      'secondary_password_recovery_supported'];
    if (optional.any((key) => raw.containsKey(key) && raw[key] is! bool)) {
      throw StateError('本人確認の設定を確認できませんでした。');
    }
    return {for (final key in ['secondary_password', 'master_feature', 'master_security', ...optional])
      key: raw[key] == true};
  }

  String? _sessionId(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      return payload is Map ? payload['session_id'] as String? : null;
    } catch (_) { return null; }
  }

  Future<String> requestProof({required String password,
      required String operation, required Map<String, dynamic> target, String? captchaToken}) async {
    final session = _client.auth.currentSession;
    final actor = session?.user.id;
    final originalSession = session == null ? null : _sessionId(session.accessToken);
    if (session == null || session.isExpired || actor == null ||
        originalSession == null || originalSession.isEmpty || password.isEmpty) {
      throw StateError('パスワードを入力して本人確認してください。');
    }
    var revoked = false;
    bool matches(Session? value) => value != null && value.user.id == actor &&
        _sessionId(value.accessToken) == originalSession;
    final subscription = _client.auth.onAuthStateChange.listen((event) {
      // Do not collapse queued A→B→A events into the current restored A.
      // JWT refresh in the same server session remains allowed.
      if (event.event == AuthChangeEvent.signedOut || !matches(event.session) ||
          !matches(_client.auth.currentSession)) {
        revoked = true;
      }
    }, onError: (Object _) { revoked = true; });
    void check() {
      if (revoked || !matches(_client.auth.currentSession) ||
          _client.auth.currentSession?.isExpired != false) {
        throw StateError('ログイン状態が変わりました。本人確認をやり直してください。');
      }
    }
    try {
      check();
      final response = await _client.functions.invoke('reauthenticate-operation',
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
        body: {'password': password, 'operation': operation, 'target': target, if (captchaToken != null) 'captcha_token': captchaToken})
          .timeout(const Duration(seconds: 30));
      check();
      final data = response.data;
      final proof = data is Map ? data['proof'] : null;
      final expiry = data is Map ? DateTime.tryParse(data['expiresAt']?.toString() ?? '') : null;
      if (response.status != 200 || data is! Map ||
          data['protocol'] != 'sko-reauthentication-v1' ||
          data['operation'] != operation || jsonEncode(data['target']) != jsonEncode(target) ||
          proof is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(proof) ||
          expiry == null || !expiry.isAfter(DateTime.now()) ||
          expiry.isAfter(DateTime.now().add(const Duration(seconds: 125)))) {
        throw StateError('本人確認を完了できませんでした。もう一度お試しください。');
      }
      return proof;
    } finally {
      await subscription.cancel();
    }
  }

  Future<int> manageAttendance({required String action,
      required List<Map<String, dynamic>> items,
      required Future<String?> Function() requestPassword}) async {
    final snapshot = jsonDecode(jsonEncode(items));
    final guard = SecondaryResetSessionGuard(
      currentSession: () => _client.auth.currentSession,
      changes: _client.auth.onAuthStateChange);
    Future<dynamic> rpc(String name, Map<String, dynamic> params) async {
      await guard.checkAfterQueuedEvents();
      final token = _client.auth.currentSession!.accessToken;
      return await _client.rpc(name, params: params)
        .setHeader('Authorization', 'Bearer $token')
        .timeout(const Duration(seconds: 30));
    }
    try {
      final capability = await capabilities();
      await guard.checkAfterQueuedEvents();
      dynamic result;
      if (capability['attendance_management'] != true) {
        result = await rpc('force_manage_attendance',
          {'p_action': action, 'p_items': snapshot});
      } else {
        final raw = await rpc('attendance_management_reauthentication_target',
          {'p_action': action, 'p_items': snapshot});
        await guard.checkAfterQueuedEvents();
        if (raw is! Map || raw['action'] != action ||
            raw['company_id'] is! String ||
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(raw['items_sha256']?.toString() ?? '') ||
            raw.keys.toSet().difference({'company_id', 'action', 'items_sha256'}).isNotEmpty) {
          throw StateError('勤怠操作の本人確認対象を確認できませんでした。');
        }
        final target = Map<String, dynamic>.from(raw);
        final password = await requestPassword();
        await guard.checkAfterQueuedEvents();
        if (password == null || password.isEmpty) {
          throw StateError('attendance_reauthentication_cancelled');
        }
        final proof = await requestProof(password: password,
          operation: 'attendance.manage', target: target);
        await guard.checkAfterQueuedEvents();
        result = await rpc('force_manage_attendance_with_proof',
          {'p_action': action, 'p_items': snapshot, 'p_proof': proof});
      }
      await guard.checkAfterQueuedEvents();
      if (result is! int) throw StateError('勤怠操作の結果を確認できませんでした。');
      return result;
    } finally {
      await guard.close();
    }
  }

  Future<void> changeSecondaryPassword(String password, String proof) async {
    await _client.rpc('change_secondary_password_with_proof',
      params: {'p_password': password, 'p_proof': proof});
  }

  Future<void> replaceSecondaryPassword(String password, String proof) async {
    await _client.rpc('replace_secondary_password_with_proof',
      params: {'p_password': password, 'p_proof': proof});
  }
}

