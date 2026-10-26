import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/secondary_entry_access.dart';

/// One page, one company, one live server session. Only an opaque grant is
/// retained in memory. Neither the password nor the grant is persisted.
class AttendanceManagementEntryAccess extends SecondaryEntryAccess {
  AttendanceManagementEntryAccess(this._client);
  final SupabaseClient _client;
  bool _prepared = false;
  bool _required = false;
  String? _actor;
  String? _sid;
  String? _company;
  String? _grant;
  DateTime? _expires;
  int _epoch = 0;
  StreamSubscription<AuthState>? _subscription;
  Timer? _timer;

  bool get prepared => _prepared;
  @override bool get requiredByServer => _required;
  @override bool get isOpen => !_required || (_grant != null &&
      _expires?.isAfter(DateTime.now()) == true && _sameSession());

  String? _sessionId(Session? session) {
    try {
      final token = session?.accessToken.split('.');
      if (token == null || token.length != 3) return null;
      final payload = jsonDecode(utf8.decode(base64Url.decode(
          base64Url.normalize(token[1]))));
      final sid = payload is Map ? payload['session_id'] : null;
      return sid is String && RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(sid) ? sid : null;
    } catch (_) { return null; }
  }

  bool _sameSession() {
    final session = _client.auth.currentSession;
    return session != null && !session.isExpired && session.user.id == _actor &&
        _sessionId(session) == _sid;
  }

  void _check(int epoch) {
    if (epoch != _epoch || !_sameSession()) {
      throw StateError('ログイン状態が変わりました。勤怠管理を開き直してください。');
    }
  }

  Future<dynamic> _rpc(String name, Map<String, dynamic> params, int epoch) async {
    _check(epoch);
    final token = _client.auth.currentSession!.accessToken;
    final result = await _client.rpc(name, params: params)
      .setHeader('Authorization', 'Bearer $token').timeout(const Duration(seconds: 30));
    await Future<void>.delayed(Duration.zero);
    _check(epoch);
    return result;
  }

  @override Future<void> prepare() async {
    await close();
    final session = _client.auth.currentSession;
    if (session == null || session.isExpired || _sessionId(session) == null) {
      throw StateError('ログイン状態を確認して、勤怠管理を開き直してください。');
    }
    _actor = session.user.id;
    _sid = _sessionId(session);
    final epoch = _epoch;
    _subscription = _client.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.signedOut ||
          event.session?.user.id != _actor || _sessionId(event.session) != _sid ||
          !_sameSession()) {
        invalidate();
      }
    }, onError: (Object _) { invalidate(); });
    dynamic raw;
    try {
      raw = await _rpc('attendance_management_entry_capabilities', const {}, epoch);
    } on PostgrestException catch (error) {
      // Only a server without this additive API uses the existing entry flow.
      if (error.code != 'PGRST202') rethrow;
      _check(epoch);
      _prepared = true;
      _required = false;
      return;
    }
    if (raw is! Map || raw['protocol'] != 'sko-attendance-entry-v1' ||
        raw['enabled'] is! bool || raw['company_id'] is! String ||
        !RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(raw['company_id'] as String) ||
        raw['ttl_seconds'] != 900) {
      throw StateError('勤怠管理の入口認証を確認できませんでした。');
    }
    _company = raw['company_id'] as String;
    _required = raw['enabled'] == true;
    _prepared = true;
  }

  @override Future<bool> unlock(String password) async {
    if (!_prepared || !_required || password.isEmpty) {
      throw StateError('勤怠管理を開き直してください。');
    }
    final epoch = _epoch;
    final raw = await _rpc('open_attendance_management_access', {
      'p_password': password, 'p_expected_company_id': _company,
    }, epoch);
    if (raw is Map && raw['protocol'] == 'sko-attendance-entry-v1' &&
        raw['ok'] == false && raw['error'] == 'invalid_password') {
      return false;
    }
    final expiry = raw is Map ? DateTime.tryParse(raw['expires_at']?.toString() ?? '') : null;
    if (raw is! Map || raw['protocol'] != 'sko-attendance-entry-v1' || raw['ok'] != true ||
        raw['company_id'] != _company || raw['grant'] is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(raw['grant'] as String) || expiry == null ||
        !expiry.isAfter(DateTime.now()) ||
        expiry.isAfter(DateTime.now().add(const Duration(seconds: 905)))) {
      throw StateError('勤怠管理の入口認証を完了できませんでした。');
    }
    _grant = raw['grant'] as String;
    _expires = expiry;
    _timer?.cancel();
    _timer = Timer(expiry.difference(DateTime.now()), invalidate);
    return true;
  }

  Future<int> manage({required String action, required List<Map<String, dynamic>> items}) async {
    final epoch = _epoch;
    if (!_prepared || !_required || !isOpen) {
      invalidate();
      throw StateError('入口認証の有効期限が切れました。勤怠管理を開き直してください。');
    }
    try {
      final raw = await _rpc('force_manage_attendance_with_access', {
        'p_action': action, 'p_items': jsonDecode(jsonEncode(items)),
        'p_access': _grant, 'p_expected_company_id': _company,
      }, epoch);
      if (raw is! int) throw StateError('勤怠操作の結果を確認できませんでした。');
      return raw;
    } catch (_) {
      // An ambiguous request never silently reuses its page authorization.
      invalidate();
      rethrow;
    }
  }

  @override void invalidate() {
    final grant = _grant;
    final sameSession = _sameSession();
    final token = sameSession ? _client.auth.currentSession?.accessToken : null;
    _epoch++;
    _grant = null;
    _expires = null;
    _timer?.cancel();
    _timer = null;
    if (grant != null && token != null) {
      unawaited(_client.rpc('close_attendance_management_access', params: {'p_access': grant})
        .setHeader('Authorization', 'Bearer $token').timeout(const Duration(seconds: 10))
        .then<void>((_) {}, onError: (Object _) {}));
    }
    notifyListeners();
  }

  @override Future<void> close() async {
    invalidate();
    await _subscription?.cancel();
    _subscription = null;
    _prepared = false;
  }
}
