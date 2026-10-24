import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

enum AppleLinkProviderStatus { enabled, disabled, unavailable }

enum AppleLinkReadiness {
  ready, linked, loginRequired, googleRequired, recentOAuthRequired,
  providerDisabled, unavailable,
}

/// Adds Apple to a signed-in Google account. Never starts Apple sign-in/signup.
class AppleAccountLink {
  AppleAccountLink(this.client, {
    required this.settingsUrl,
    required this.publicKey,
    Future<bool> Function()? providerCheck,
    Future<bool> Function(Uri)? launch,
  }) : _providerCheck = providerCheck,
       _launch = launch ?? ((uri) => launchUrl(uri));

  final SupabaseClient client;
  final Uri settingsUrl;
  final String publicKey;
  final Future<bool> Function()? _providerCheck;
  final Future<bool> Function(Uri) _launch;
  StreamSubscription<AuthState>? _subscription;
  String? _actor;
  bool _revoked = false;
  bool _pending = false;
  int _generation = 0;
  String? _membershipBefore;
  String? _googleIdentityBefore;

  static const redirect = 'com.skworks.sko://login-callback/';
  Stream<AuthState> get changes => client.auth.onAuthStateChange;
  bool get pending => _pending && !_revoked;

  Future<bool> providerEnabled() async =>
      await providerStatus() == AppleLinkProviderStatus.enabled;

  Future<AppleLinkProviderStatus> providerStatus() async {
    final check = _providerCheck;
    if (check != null) {
      try {
        return await check() ? AppleLinkProviderStatus.enabled
            : AppleLinkProviderStatus.disabled;
      } catch (_) { return AppleLinkProviderStatus.unavailable; }
    }
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await http.getUrl(settingsUrl).timeout(const Duration(seconds: 10));
      request.followRedirects = false;
      request.headers.set('apikey', publicKey);
      final response = await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode != 200 || response.contentLength > 65536) {
        return AppleLinkProviderStatus.unavailable;
      }
      final bytes = await response.timeout(const Duration(seconds: 10))
          .fold<List<int>>(<int>[], (bytes, chunk) {
        if (bytes.length + chunk.length > 65536) {
          throw StateError('apple_settings_too_large');
        }
        bytes.addAll(chunk);
        return bytes;
      }).timeout(const Duration(seconds: 10));
      final body = utf8.decode(bytes);
      final json = jsonDecode(body);
      if (json is! Map || json['external'] is! Map ||
          json['external']['apple'] is! bool) {
        return AppleLinkProviderStatus.unavailable;
      }
      return json['external']['apple'] == true
          ? AppleLinkProviderStatus.enabled : AppleLinkProviderStatus.disabled;
    } catch (_) {
      return AppleLinkProviderStatus.unavailable;
    } finally { http.close(force: true); }
  }

  /// Read-only preflight. It neither refreshes/signs in nor starts a link URL.
  /// A fresh verified token is still required again by begin().
  Future<AppleLinkReadiness> readiness() async {
    final initial = client.auth.currentSession;
    if (initial == null || initial.isExpired) {
      return AppleLinkReadiness.loginRequired;
    }
    final actor = initial.user.id, token = initial.accessToken;
    var revoked = false;
    final subscription = changes.listen((event) {
      if (event.event == AuthChangeEvent.signedOut ||
          client.auth.currentSession?.accessToken != token ||
          client.auth.currentSession?.user.id != actor) {
        revoked = true;
      }
    }, onError: (Object _) { revoked = true; });
    void check() {
      if (revoked || client.auth.currentSession?.user.id != actor ||
          client.auth.currentSession?.accessToken != token ||
          client.auth.currentSession?.isExpired != false) {
        throw StateError('apple_link_session_changed');
      }
    }
    Future<AppleLinkReadiness> inspect() async {
      final user = (await client.auth.getUser(token)
          .timeout(const Duration(seconds: 10))).user;
      check();
      if (user == null || user.id != actor || user.toJson()['is_anonymous'] == true) {
        return AppleLinkReadiness.unavailable;
      }
      if (!_has(user, 'google')) {
        return AppleLinkReadiness.googleRequired;
      }
      if (_has(user, 'apple')) {
        return AppleLinkReadiness.linked;
      }
      final provider = await providerStatus();
      check();
      if (provider == AppleLinkProviderStatus.unavailable) {
        return AppleLinkReadiness.unavailable;
      }
      if (provider == AppleLinkProviderStatus.disabled) {
        return AppleLinkReadiness.providerDisabled;
      }
      if (!_recentOAuth(token)) {
        return AppleLinkReadiness.recentOAuthRequired;
      }
      final rows = await client.from('company_members').select('company_id,role')
          .eq('user_id', actor).setHeader('Authorization', 'Bearer $token')
          .timeout(const Duration(seconds: 10));
      check();
      if (rows.isEmpty) {
        return AppleLinkReadiness.unavailable;
      }
      return AppleLinkReadiness.ready;
    }
    AppleLinkReadiness result;
    try { result = await inspect(); }
    catch (_) { result = AppleLinkReadiness.unavailable; }
    finally { await subscription.cancel(); }
    try { check(); return result; }
    catch (_) { return AppleLinkReadiness.unavailable; }
  }

  void _checkActor(int generation) {
    final session = client.auth.currentSession;
    if (generation != _generation || _revoked || _actor == null || session?.user.id != _actor ||
        session?.isExpired != false) {
      throw StateError('apple_link_session_changed');
    }
  }

  Future<User> _verifiedUser(int generation) async {
    _checkActor(generation);
    final token = client.auth.currentSession!.accessToken;
    final user = (await client.auth.getUser(token)
        .timeout(const Duration(seconds: 10))).user;
    _checkActor(generation);
    if (user == null || user.id != _actor ||
        client.auth.currentSession?.accessToken != token ||
        user.toJson()['is_anonymous'] == true) {
      throw StateError('apple_link_session_changed');
    }
    return user;
  }

  bool _has(User user, String provider) =>
      user.identities?.any((value) => value.provider == provider) == true;

  String _googleIdentity(User user) {
    final identities = (user.identities ?? <UserIdentity>[])
        .where((value) => value.provider == 'google')
        .map((value) => jsonEncode({'id': value.id,
          'identity_id': value.identityId, 'user_id': value.userId}))
        .toList()..sort();
    return jsonEncode(identities);
  }

  Future<String> _memberships(int generation) async {
    _checkActor(generation);
    final token = client.auth.currentSession!.accessToken;
    final rows = await client.from('company_members').select('company_id,role')
        .eq('user_id', _actor!)
        .setHeader('Authorization', 'Bearer $token')
        .timeout(const Duration(seconds: 10));
    _checkActor(generation);
    if (client.auth.currentSession?.accessToken != token || rows.isEmpty) {
      throw StateError('apple_link_membership_unavailable');
    }
    final values = rows.map((row) => jsonEncode({
      'company_id': row['company_id'], 'role': row['role'],
    })).toList()..sort();
    return jsonEncode(values);
  }

  bool _recentOAuth(String token) {
    try {
      final json = jsonDecode(utf8.decode(base64Url.decode(
          base64Url.normalize(token.split('.')[1]))));
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return json is Map && json['amr'] is List &&
          (json['amr'] as List).any((value) => value is Map &&
              value['method'] == 'oauth' && value['timestamp'] is int &&
              (value['timestamp'] as int) <= now &&
              now - (value['timestamp'] as int) <= 300);
    } catch (_) { return false; }
  }

  Future<void> begin() async {
    if (_pending) throw StateError('apple_link_already_pending');
    final initial = client.auth.currentSession;
    if (initial == null || initial.isExpired) {
      throw StateError('apple_link_login_required');
    }
    final generation = ++_generation;
    _actor = initial.user.id;
    _revoked = false;
    _pending = true;
    _subscription = changes.listen((state) {
      if (state.event == AuthChangeEvent.signedOut ||
          client.auth.currentSession?.user.id != _actor) {
        _revoked = true;
      }
    }, onError: (Object _) { _revoked = true; });
    try {
      final user = await _verifiedUser(generation);
      if (!_has(user, 'google') || _has(user, 'apple')) {
        throw StateError('apple_link_existing_google_required');
      }
      // Check the AMR only after the exact access token was verified above.
      if (!_recentOAuth(client.auth.currentSession!.accessToken)) {
        throw StateError('apple_link_recent_google_required');
      }
      _googleIdentityBefore = _googleIdentity(user);
      _membershipBefore = await _memberships(generation);
      if (!await providerEnabled()) throw StateError('apple_link_not_configured');
      _checkActor(generation);
      // Obtain, then check the session before launching. The SDK may await PKCE
      // storage before reading its current JWT; a revoked operation never opens
      // a URL obtained for another account.
      final response = await client.auth.getLinkIdentityUrl(OAuthProvider.apple,
          redirectTo: redirect).timeout(const Duration(seconds: 15));
      _checkActor(generation);
      final uri = Uri.parse(response.url);
      if (uri.scheme != 'https' || uri.host != 'appleid.apple.com' ||
          uri.userInfo.isNotEmpty || uri.port != 443) {
        throw StateError('apple_link_invalid_authorize_url');
      }
      if (!await _launch(uri)) throw StateError('apple_link_launch_failed');
      _checkActor(generation);
    } catch (_) {
      if (generation == _generation) await cancel();
      rethrow;
    }
  }

  Future<bool> verifyCompletion() async {
    if (_pending && _revoked) throw StateError('apple_link_session_changed');
    if (!pending) return false;
    final generation = _generation;
    final user = await _verifiedUser(generation);
    if (!_has(user, 'apple')) return false;
    if (!_has(user, 'google') || _googleIdentity(user) != _googleIdentityBefore) {
      throw StateError('apple_link_google_missing');
    }
    if (await _memberships(generation) != _membershipBefore) {
      throw StateError('apple_link_membership_changed');
    }
    await cancel();
    return true;
  }

  Future<void> cancel() async {
    _generation++;
    _revoked = true;
    _pending = false;
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<void> dispose() async {
    await cancel();
  }
}
