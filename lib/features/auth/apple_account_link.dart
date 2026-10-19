import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

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

  Future<bool> providerEnabled() async {
    final check = _providerCheck;
    if (check != null) return check();
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await http.getUrl(settingsUrl).timeout(const Duration(seconds: 10));
      request.followRedirects = false;
      request.headers.set('apikey', publicKey);
      final response = await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode != 200 || response.contentLength > 65536) return false;
      final bytes = await response.timeout(const Duration(seconds: 10))
          .fold<List<int>>(<int>[], (bytes, chunk) {
        if (bytes.length + chunk.length > 65536) {
          throw StateError('apple_settings_too_large');
        }
        bytes.addAll(chunk);
        return bytes;
      });
      final body = utf8.decode(bytes);
      final json = jsonDecode(body);
      return json is Map && json['external'] is Map &&
          json['external']['apple'] == true;
    } catch (_) {
      return false;
    } finally { http.close(force: true); }
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
