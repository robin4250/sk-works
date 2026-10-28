import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Default-OFF, memory-only verification before any application-session adoption.
/// The received refresh credential stays inside an isolated SDK client. This
/// class does not write SharedPreferences, change the application client, open a
/// public route, or claim that SDK verification is global session adoption.
class AppleSuccessorClientPreparation with WidgetsBindingObserver {
  AppleSuccessorClientPreparation(this.applicationClient, {
    required this.projectUrl,
    required this.publicKey,
    this.enabled = const bool.fromEnvironment('SKO_APPLE_SUCCESSOR_PREPARATION', defaultValue: false),
    SupabaseClient Function()? isolatedClientFactory,
    Stream<AuthState>? authChanges,
  }) : _isolatedClientFactory = isolatedClientFactory,
       _authChanges = authChanges;

  // One preparation owns a given application client at a time. This protects
  // against duplicate route/controller instances; it is not a global SDK CAS.
  static final _owners = Expando<AppleSuccessorClientPreparation>();
  final SupabaseClient applicationClient;
  final String projectUrl;
  final String publicKey;
  final bool enabled;
  final SupabaseClient Function()? _isolatedClientFactory;
  final Stream<AuthState>? _authChanges;
  StreamSubscription<AuthState>? _subscription;
  SupabaseClient? _preparedClient;
  bool _attempted = false, _disposed = false, _ready = false;
  int _generation = 0;
  String? _originalActor, _originalAccessToken, _successorAccessToken;

  // Auth events are not a complete SDK mutation log. In particular, a restored
  // same-UID session may be installed without the stream used by this instance
  // observing a transition. Recheck scalar bindings whenever readiness is read.
  // This still does not provide a global session-write CAS or ABA guarantee.
  bool get ready {
    if (!_ready || _disposed) { return false; }
    final current = applicationClient.auth.currentSession;
    final prepared = _preparedClient?.auth.currentSession;
    if (current == null || current.isExpired || current.user.id != _originalActor ||
        current.accessToken != _originalAccessToken || prepared == null ||
        prepared.isExpired || prepared.user.id != _originalActor ||
        prepared.accessToken != _successorAccessToken) {
      invalidate();
      return false;
    }
    return true;
  }

  static final _uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');
  static StateError _failure() => StateError('ログイン状態の確認を完了できませんでした。再ログインして確認してください。');

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      invalidate();
    }
  }

  void invalidate() {
    _generation++;
    _ready = false;
    _originalActor = _originalAccessToken = _successorAccessToken = null;
    if (identical(_owners[applicationClient], this)) {
      _owners[applicationClient] = null;
    }
    final prepared = _preparedClient;
    _preparedClient = null;
    if (prepared != null) { unawaited(prepared.dispose()); }
  }

  Future<void> dispose() async {
    _disposed = true;
    invalidate();
    WidgetsBinding.instance.removeObserver(this);
    await _subscription?.cancel();
    _subscription = null;
  }

  String _google(User user) {
    final identities = (user.identities ?? <UserIdentity>[])
        .where((identity) => identity.provider == 'google' && identity.userId == user.id)
        .map((identity) => jsonEncode([identity.id, identity.identityId, identity.userId]))
        .toList()..sort();
    if (identities.isEmpty || user.isAnonymous) { throw _failure(); }
    return jsonEncode(identities);
  }

  String _sessionId(String token, String actor) {
    try {
      final pieces = token.split('.');
      if (pieces.length != 3) { throw _failure(); }
      final claims = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(pieces[1]))));
      if (claims is! Map || claims['sub'] != actor || claims['session_id'] is! String ||
          !_uuid.hasMatch(claims['session_id'] as String)) { throw _failure(); }
      return claims['session_id'] as String;
    } catch (_) {
      throw _failure();
    }
  }

  Future<String> _memberships(SupabaseClient client, String actor, String token) async {
    final rows = await client.from('company_members').select('company_id,role')
        .eq('user_id', actor).setHeader('Authorization', 'Bearer $token')
        .timeout(const Duration(seconds: 15));
    if (rows.isEmpty) { throw _failure(); }
    final values = rows.map((row) {
      if (row['company_id'] is! String || row['role'] is! String) { throw _failure(); }
      return jsonEncode([row['company_id'], row['role']]);
    }).toList()..sort();
    return jsonEncode(values);
  }

  /// Call before sending the enrollment request. receiveOnce must be the
  /// reviewed same-request HTTPS transport, not a retrying credential cache.
  /// Successful completion means isolated preparation only; ready exposes no
  /// credential and no application Auth session has been adopted.
  Future<void> prepare({required String requestId,
    required Future<Map<String, dynamic>> Function() receiveOnce}) async {
    if (_disposed || !enabled || kIsWeb || defaultTargetPlatform != TargetPlatform.iOS ||
        _attempted || _owners[applicationClient] != null || !_uuid.hasMatch(requestId)) { throw _failure(); }
    _attempted = true;
    final origin = Uri.tryParse(projectUrl);
    if (origin == null || origin.scheme != 'https' || origin.userInfo.isNotEmpty ||
        origin.hasQuery || origin.hasFragment || origin.path.isNotEmpty && origin.path != '/' || publicKey.isEmpty) {
      throw _failure();
    }
    final initial = applicationClient.auth.currentSession;
    if (initial == null || initial.isExpired || !_uuid.hasMatch(initial.user.id)) { throw _failure(); }
    _owners[applicationClient] = this;
    final actor = initial.user.id, originalToken = initial.accessToken;
    final generation = ++_generation;
    void check() {
      final current = applicationClient.auth.currentSession;
      if (_disposed || generation != _generation || current == null || current.isExpired ||
          current.user.id != actor || current.accessToken != originalToken) { throw _failure(); }
    }
    _subscription = (_authChanges ?? applicationClient.auth.onAuthStateChange).listen((event) {
      if (event.event == AuthChangeEvent.signedOut || event.session?.user.id != actor ||
          event.session?.accessToken != originalToken) { invalidate(); }
    }, onError: (Object _) => invalidate(), onDone: invalidate);
    WidgetsBinding.instance.addObserver(this);
    SupabaseClient? isolated;
    try {
      final original = (await applicationClient.auth.getUser(originalToken)
          .timeout(const Duration(seconds: 15))).user;
      check();
      if (original == null || original.id != actor) { throw _failure(); }
      final originalSessionId = _sessionId(originalToken, actor);
      final google = _google(original);
      final companies = await _memberships(applicationClient, actor, originalToken);
      check();
      final raw = await receiveOnce().timeout(const Duration(minutes: 3));
      await Future<void>.delayed(Duration.zero);
      check();
      const fields = {'schema', 'request_id', 'user_id', 'session_id', 'token_type', 'access_token', 'refresh_token'};
      if (raw.length != fields.length || raw.keys.any((key) => !fields.contains(key)) ||
          raw['schema'] != 1 || raw['request_id'] != requestId || raw['user_id'] != actor ||
          raw['session_id'] is! String || !_uuid.hasMatch(raw['session_id'] as String) || raw['session_id'] == originalSessionId ||
          raw['token_type'] != 'bearer') {
        throw _failure();
      }
      final access = raw['access_token'], refresh = raw['refresh_token'];
      if (access is! String || access.isEmpty || access.length > 16384 ||
          refresh is! String || refresh.isEmpty || refresh.length > 16384) { throw _failure(); }
      // Consistency checks only; the isolated SDK's getUser verifies the token
      // with Auth. A fresh access token prevents setSession's refresh fallback.
      final pieces = access.split('.');
      if (pieces.length != 3) { throw _failure(); }
      final claims = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(pieces[1]))));
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (claims is! Map || claims['sub'] != actor || claims['session_id'] != raw['session_id'] ||
          claims['exp'] is! int || (claims['exp'] as int) <= now + 120 ||
          claims['iss'] != '${projectUrl.replaceFirst(RegExp(r'/$'), '')}/auth/v1' ||
          !(claims['aud'] == 'authenticated' || claims['aud'] is List &&
              (claims['aud'] as List).length == 1 && (claims['aud'] as List).single == 'authenticated')) { throw _failure(); }
      isolated = _isolatedClientFactory?.call() ?? SupabaseClient(projectUrl, publicKey,
          authOptions: const AuthClientOptions(autoRefreshToken: false));
      if (identical(isolated, applicationClient) || isolated.auth.currentSession != null) { throw _failure(); }
      final response = await isolated.auth.setSession(refresh, accessToken: access)
          .timeout(const Duration(seconds: 15));
      check();
      final verified = response.user, session = response.session;
      if (verified == null || verified.id != actor || session?.accessToken != access ||
          session?.refreshToken != refresh || _google(verified) != google ||
          verified.identities?.where((identity) => identity.provider == 'apple' && identity.userId == actor).length != 1) {
        throw _failure();
      }
      if (await _memberships(isolated, actor, access) != companies) { throw _failure(); }
      await Future<void>.delayed(Duration.zero);
      check();
      if ((claims['exp'] as int) <= DateTime.now().millisecondsSinceEpoch ~/ 1000 + 60) { throw _failure(); }
      _preparedClient = isolated;
      isolated = null;
      _originalActor = actor;
      _originalAccessToken = originalToken;
      _successorAccessToken = access;
      _ready = true;
    } catch (_) {
      invalidate();
      throw _failure();
    } finally {
      if (isolated != null && !identical(isolated, applicationClient)) { await isolated.dispose(); }
      if (!_ready) {
        await _subscription?.cancel();
        _subscription = null;
        WidgetsBinding.instance.removeObserver(this);
      }
    }
  }
}

