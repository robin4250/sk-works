import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import '../../international/countries/jp/japan_phone_rules.dart';

class PrimaryPasswordReauthenticationRequired implements Exception {
  const PrimaryPasswordReauthenticationRequired();
}

class LoginMethodEnrollmentState {
  const LoginMethodEnrollmentState({required this.email, required this.phone,
    required this.emailConfirmed, required this.phoneConfirmed,
    required this.emailAvailable, required this.phoneAvailable});
  final String email, phone;
  final bool emailConfirmed, phoneConfirmed, emailAvailable, phoneAvailable;
  bool get canSetPassword =>
      (emailAvailable && emailConfirmed && email.isNotEmpty) ||
      (phoneAvailable && phoneConfirmed && phone.isNotEmpty);
}

abstract interface class LoginMethodEnrollmentSource {
  Future<LoginMethodEnrollmentState> load();
  Future<void> requestPhone(String phone);
  Future<void> confirmPhone(String code);
  Future<void> requestEmail(String email);
  Future<void> setPrimaryPassword(String password, {String? nonce});
  Future<void> requestPrimaryPasswordCode();
  void cancelPhone();
  void dispose();
}

/// Adds credentials to the captured, server-verified user. No signup, sign-in,
/// password recovery, identity unlinking or secondary-password RPC is used.
class LoginMethodEnrollmentRepository implements LoginMethodEnrollmentSource {
  LoginMethodEnrollmentRepository(this.client, {required this.authUrl,
    required this.publicKey, http.Client? transport})
      : _http = transport ?? http.Client(), _ownsHttp = transport == null,
        _actorAtCreation = client.auth.currentUser?.id {
    _lifetime = client.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.signedOut ||
          client.auth.currentUser?.id != _actorAtCreation) {
        _invalidated = true;
        cancelPhone();
      }
    }, onError: (Object _) { _invalidated = true; cancelPhone(); });
  }
  final SupabaseClient client;
  final Uri authUrl;
  final String publicKey;
  final http.Client _http;
  final bool _ownsHttp;
  final String? _actorAtCreation;
  late final StreamSubscription<AuthState> _lifetime;
  bool _invalidated = false;
  String? _pendingPhone, _pendingActor;
  int _generation = 0;
  bool _busy = false, _disposed = false;

  static LoginMethodEnrollmentRepository? maybeCreate() =>
      SupabaseBackend.isInitialized && SupabaseBackendConfig.isConfigured
          ? LoginMethodEnrollmentRepository(SupabaseBackend.client,
              authUrl: Uri.parse('${SupabaseBackendConfig.url}/auth/v1/'),
              publicKey: SupabaseBackendConfig.publishableKey)
          : null;

  Future<Map<String, dynamic>> _request(String route, String token,
      {String method = 'GET', Map<String, dynamic>? body}) async {
    final uri = authUrl.resolve(route);
    if (uri.origin != authUrl.origin || !uri.path.startsWith(authUrl.path)) {
      throw StateError('本人確認先を確認できません。');
    }
    final request = http.Request(method, uri)
      ..followRedirects = false
      ..headers.addAll({'apikey': publicKey, 'Authorization': 'Bearer $token',
        'Content-Type': 'application/json'});
    if (body != null) request.body = jsonEncode(body);
    final response = await _http.send(request).timeout(const Duration(seconds: 15));
    final bytes = await response.stream.fold<List<int>>(<int>[], (bytes, chunk) {
      if (bytes.length + chunk.length > 65536) throw StateError('応答を確認できません。');
      bytes.addAll(chunk);
      return bytes;
    }).timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      try {
        final error = jsonDecode(utf8.decode(bytes));
        if (error is Map && (error['code'] ?? error['error_code']) == 'reauthentication_needed') {
          throw const PrimaryPasswordReauthenticationRequired();
        }
      } on PrimaryPasswordReauthenticationRequired { rethrow; } catch (_) {}
      // Do not expose raw Auth replies, credentials, tokens or recipient values.
      throw StateError('登録を完了できませんでした。設定と入力内容を確認してください。');
    }
    final value = bytes.isEmpty ? <String, dynamic>{} : jsonDecode(utf8.decode(bytes));
    if (value is! Map) throw StateError('登録結果を確認できません。');
    return Map<String, dynamic>.from(value);
  }

  Future<T> _bound<T>(Future<T> Function(String, User, void Function()) action) async {
    if (_busy || _disposed) throw StateError('処理中です。');
    if (_invalidated || client.auth.currentUser?.id != _actorAtCreation) {
      throw StateError('ログイン状態が変わりました。設定を開き直してください。');
    }
    final session = client.auth.currentSession;
    if (session == null || session.isExpired) throw StateError('ログインを確認してください。');
    _busy = true;
    final generation = _generation;
    var revoked = false;
    final actor = session.user.id, token = session.accessToken;
    void check() {
      if (_disposed || revoked || generation != _generation ||
          client.auth.currentSession?.user.id != actor ||
          client.auth.currentSession?.accessToken != token ||
          client.auth.currentSession?.isExpired != false) {
        throw StateError('ログイン状態が変わりました。設定を開き直してください。');
      }
    }
    final subscription = client.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.signedOut ||
          client.auth.currentSession?.user.id != actor ||
          client.auth.currentSession?.accessToken != token) revoked = true;
    }, onError: (Object _) { revoked = true; });
    try {
      final user = (await client.auth.getUser(token)).user;
      check();
      if (user == null || user.id != actor || user.toJson()['is_anonymous'] == true) {
        throw StateError('本人のアカウントを確認できません。');
      }
      return await action(token, user, check);
    } finally {
      await subscription.cancel();
      _busy = false;
    }
  }

  Future<LoginMethodEnrollmentState> _state(String token, User user,
      void Function() check) async {
    final settings = await _request('settings', token);
    check();
    final external = settings['external'];
    if (external is! Map) throw StateError('ログイン方法の提供状態を確認できません。');
    final json = user.toJson();
    return LoginMethodEnrollmentState(email: user.email ?? '', phone: user.phone ?? '',
      emailConfirmed: json['email_confirmed_at'] != null,
      phoneConfirmed: json['phone_confirmed_at'] != null,
      emailAvailable: external['email'] == true, phoneAvailable: external['phone'] == true);
  }

  @override
  Future<LoginMethodEnrollmentState> load() => _bound((token, user, check) =>
      _state(token, user, check));

  Future<String> _memberships(String token, String actor, void Function() check) async {
    final rows = await client.from('company_members').select('company_id,role')
        .eq('user_id', actor).setHeader('Authorization', 'Bearer $token');
    check();
    if (rows.isEmpty) throw StateError('会社への所属を確認できません。');
    final values = rows.map((row) => jsonEncode({'company_id': row['company_id'],
      'role': row['role']})).toList()..sort();
    return jsonEncode(values);
  }

  Future<void> _verify(String token, User before, String roles,
      void Function() check) async {
    check();
    final after = (await client.auth.getUser(token)).user;
    check();
    if (after == null || after.id != before.id ||
        after.toJson()['is_anonymous'] == true) throw StateError('本人を確認できません。');
    for (final identity in before.identities ?? <UserIdentity>[]) {
      if (!(after.identities ?? <UserIdentity>[]).any((value) =>
          value.provider == identity.provider && value.id == identity.id &&
          value.identityId == identity.identityId && value.userId == identity.userId)) {
        throw StateError('既存のログイン方法を確認できません。');
      }
    }
    if (await _memberships(token, before.id, check) != roles) {
      throw StateError('会社への所属状態が変わりました。');
    }
  }

  @override
  Future<void> requestPhone(String phone) => _bound((token, user, check) async {
    if (!JapanPhoneRules.isSupportedMobile(phone)) throw StateError('携帯電話番号を確認してください。');
    final state = await _state(token, user, check);
    if (!state.phoneAvailable) throw StateError('電話番号ログインは現在準備中です。');
    final normalized = JapanPhoneRules.normalize(phone);
    if (state.phoneConfirmed && state.phone.isNotEmpty) throw StateError('登録済み電話番号は保持します。変更はプロフィールから行ってください。');
    final roles = await _memberships(token, user.id, check);
    check();
    await _request('user', token, method: 'PUT', body: {'phone': normalized});
    await _verify(token, user, roles, check);
    _pendingPhone = normalized;
    _pendingActor = user.id;
  });

  @override
  Future<void> confirmPhone(String code) => _bound((token, user, check) async {
    final phone = _pendingPhone;
    if (_pendingActor != user.id || phone == null || !RegExp(r'^\d{6}$').hasMatch(code.trim())) {
      throw StateError('SMSの6桁コードを確認してください。');
    }
    final state = await _state(token, user, check);
    if (!state.phoneAvailable) throw StateError('電話番号ログインは現在準備中です。');
    final roles = await _memberships(token, user.id, check);
    check();
    // Use captured bearer. Do not install a returned session over a newer login.
    await _request('verify', token, method: 'POST',
        body: {'type': 'phone_change', 'phone': phone, 'token': code.trim()});
    await _verify(token, user, roles, check);
    final after = (await client.auth.getUser(token)).user;
    check();
    if (after?.phone != phone || after?.toJson()['phone_confirmed_at'] == null) {
      throw StateError('番号の確認結果を取得できません。再読み込みしてください。');
    }
    _pendingPhone = null;
    _pendingActor = null;
  });

  @override
  Future<void> requestEmail(String email) => _bound((token, user, check) async {
    final value = email.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)) throw StateError('メールアドレスを確認してください。');
    final state = await _state(token, user, check);
    if (!state.emailAvailable) throw StateError('メールログインは現在準備中です。');
    if (state.email.isNotEmpty) throw StateError('登録済みのメールアドレスを保持します。');
    final roles = await _memberships(token, user.id, check);
    check();
    await _request('user?redirect_to=${Uri.encodeQueryComponent('com.skworks.sko://login-callback/')}',
        token, method: 'PUT', body: {'email': value});
    await _verify(token, user, roles, check);
  });

  @override
  Future<void> setPrimaryPassword(String password, {String? nonce}) => _bound((token, user, check) async {
    if (password.length < 8) throw StateError('8文字以上で設定してください。');
    final state = await _state(token, user, check);
    if (!state.canSetPassword) throw StateError('先にメールまたは電話番号の所有確認を完了してください。');
    final roles = await _memberships(token, user.id, check);
    check();
    await _request('user', token, method: 'PUT', body: {'password': password, if (nonce != null) 'nonce': nonce});
    await _verify(token, user, roles, check);
  });

  @override
  Future<void> requestPrimaryPasswordCode() => _bound((token, user, check) async {
    final state = await _state(token, user, check);
    if (!state.canSetPassword) throw StateError('先にメールまたは電話番号の確認を完了してください。');
    check();
    await _request('reauthenticate', token);
    check();
  });

  @override
  void cancelPhone() { _generation++; _pendingPhone = null; _pendingActor = null; }
  @override
  void dispose() { _disposed = true; cancelPhone(); _lifetime.cancel(); if (_ownsHttp) _http.close(); }
}
