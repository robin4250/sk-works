import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Memory-only input for the reviewed server flow; never a login or operation proof.
class PreparedAppleCredential {
  const PreparedAppleCredential({required this.actorId, required this.exactAccessToken,
    required this.idToken, required this.nonce});
  final String actorId;
  final String exactAccessToken;
  final String idToken;
  final String nonce;
}

/// Default OFF. No sign-in, identity link, session adoption, or profile write.
/// Native registration and server enrollment must be reviewed before UI wiring.
class AppleNativeCredentialPreparation with WidgetsBindingObserver {
  AppleNativeCredentialPreparation(this.client, {
    this.enabled = const bool.fromEnvironment('SKO_APPLE_NATIVE_PREPARATION', defaultValue: false),
    this.channel = const MethodChannel('com.skworks.sko/apple_credential'),
    this.credentialTimeout = const Duration(minutes: 3),
    Stream<AuthState>? authChanges,
  }) : _authChanges = authChanges;
  final SupabaseClient client;
  final bool enabled;
  final MethodChannel channel;
  final Stream<AuthState>? _authChanges;
  final Duration credentialTimeout;
  bool _busy = false;
  bool _disposed = false;
  VoidCallback? _invalidateActive;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _invalidateActive?.call();
    }
  }

  void dispose() {
    _disposed = true;
    _invalidateActive?.call();
    WidgetsBinding.instance.removeObserver(this);
  }

  Future<void> _cancelNative(String requestId) async {
    try {
      await channel.invokeMethod<Object?>('cancelAppleCredential', {'request_id': requestId})
        .timeout(const Duration(seconds: 2));
    } catch (_) { /* Cancellation cannot authorize or return credentials. */ }
  }

  Future<PreparedAppleCredential> requestForExistingGoogleAccount() async {
    if (_disposed || !enabled || kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      throw StateError('Appleによるログインは準備中です。');
    }
    if (credentialTimeout <= Duration.zero || credentialTimeout > const Duration(minutes: 3)) {
      throw StateError('Appleの本人確認を開始できませんでした。');
    }
    if (_busy) throw StateError('Appleの本人確認を進めています。');
    final session = client.auth.currentSession;
    final actor = session?.user.id;
    if (session == null || session.isExpired || actor == null) {
      throw StateError('ログイン状態を確認できませんでした。');
    }
    final token = session.accessToken;
    _busy = true;
    var revoked = false;
    final random = Random.secure();
    final requestId = List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    void invalidate() {
      revoked = true;
      unawaited(_cancelNative(requestId));
    }
    _invalidateActive = invalidate;
    WidgetsBinding.instance.addObserver(this);
    bool matches(Session? value) => value != null && !value.isExpired &&
      value.user.id == actor && value.accessToken == token;
    final subscription = (_authChanges ?? client.auth.onAuthStateChange).listen((event) {
      if (event.event == AuthChangeEvent.signedOut || !matches(event.session) ||
          !matches(client.auth.currentSession)) { invalidate(); }
    }, onError: (Object _) { invalidate(); }, onDone: invalidate);
    void check() {
      if (revoked || !matches(client.auth.currentSession)) {
        throw StateError('ログイン状態が変わりました。本人確認をやり直してください。');
      }
    }
    try {
      check();
      final user = (await client.auth.getUser(token).timeout(const Duration(seconds: 15))).user;
      await Future<void>.delayed(Duration.zero);
      check();
      if (user == null || user.id != actor || user.isAnonymous ||
          user.identities?.any((identity) => identity.provider == 'google' && identity.userId == actor) != true) {
        throw StateError('現在のGoogleアカウントを確認できませんでした。');
      }
      final raw = await channel.invokeMethod<Object?>('requestAppleCredential', {'request_id': requestId})
        .timeout(credentialTimeout);
      await Future<void>.delayed(Duration.zero);
      check();
      if (raw is! Map || raw.keys.toSet().difference({'id_token', 'nonce'}).isNotEmpty ||
          raw.length != 2 || raw['id_token'] is! String || raw['nonce'] is! String) {
        throw StateError('Appleの本人確認を完了できませんでした。');
      }
      final idToken = raw['id_token'] as String;
      final nonce = raw['nonce'] as String;
      if (idToken.isEmpty || idToken.length > 16384 ||
          idToken.split('.').length != 3 || !RegExp(r'^[A-Za-z0-9_-]{43,128}$').hasMatch(nonce)) {
        throw StateError('Appleの本人確認を完了できませんでした。');
      }
      return PreparedAppleCredential(actorId: actor, exactAccessToken: token,
        idToken: idToken, nonce: nonce);
    } on TimeoutException {
      throw StateError('Appleの本人確認が時間切れになりました。もう一度お試しください。');
    } on MissingPluginException {
      throw StateError('Appleによるログインは準備中です。');
    } on PlatformException {
      throw StateError('Appleの本人確認を完了できませんでした。');
    } finally {
      _invalidateActive = null;
      WidgetsBinding.instance.removeObserver(this);
      unawaited(_cancelNative(requestId));
      await subscription.cancel();
      _busy = false;
    }
  }
}
