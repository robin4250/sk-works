import 'dart:convert';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PanelSevenSnapshot {
  const PanelSevenSnapshot({
    required this.actorId,
    required this.providers,
    required this.email,
    required this.phone,
    required this.emailConfirmed,
    required this.phoneConfirmed,
    required this.sessionMethods,
    required this.secondaryConfigured,
    this.biometricEnabled,
    this.biometricAvailable,
    required String accessToken,
  }) : _accessToken = accessToken;
  final String actorId;
  final List<String> providers;
  final String? email;
  final String? phone;
  final bool emailConfirmed;
  final bool phoneConfirmed;
  final List<String> sessionMethods;
  final bool? secondaryConfigured;
  final bool? biometricEnabled;
  final bool? biometricAvailable;
  final String _accessToken;
}

/// Reads only the currently authenticated user's Auth record and secondary
/// configuration boolean. Never creates, links, confirms or resets identities.
abstract interface class PanelSevenSource {
  Stream<AuthState> get changes;
  bool isCurrent(PanelSevenSnapshot snapshot);
  Future<PanelSevenSnapshot> load();
}

class PanelSevenRepository implements PanelSevenSource {
  PanelSevenRepository(this.client, {this.biometricAvailability});
  final Future<bool> Function()? biometricAvailability;
  final SupabaseClient client;

  @override
  Stream<AuthState> get changes => client.auth.onAuthStateChange;

  @override
  bool isCurrent(PanelSevenSnapshot snapshot) {
    final session = client.auth.currentSession;
    return session?.user.id == snapshot.actorId &&
        session?.accessToken == snapshot._accessToken &&
        session?.isExpired == false;
  }

  @override
  Future<PanelSevenSnapshot> load() async {
    final session = client.auth.currentSession;
    if (session == null || session.isExpired) {
      throw StateError('account_session_unavailable');
    }
    final actor = session.user.id;
    final token = session.accessToken;
    bool unchanged() => client.auth.currentSession?.user.id == actor &&
        client.auth.currentSession?.accessToken == token &&
        client.auth.currentSession?.isExpired == false;
    final response = await client.auth.getUser(token).timeout(const Duration(seconds: 10));
    final user = response.user;
    if (user == null || user.id != actor || !unchanged()) {
      throw StateError('account_session_changed');
    }
    final json = user.toJson();
    if (json['is_anonymous'] == true) {
      throw StateError('account_identity_unavailable');
    }
    bool? secondary;
    try {
      final raw = await client.rpc('secondary_password_configured')
          .setHeader('Authorization', 'Bearer $token')
          .timeout(const Duration(seconds: 10));
      if (raw is bool) {
        secondary = raw;
      }
    } catch (_) {
      // Unknown stays unknown. Do not expose upstream errors or assume false.
    }
    if (!unchanged()) throw StateError('account_session_changed');
    bool? biometricEnabled;
    bool? biometricAvailable;
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 5));
      biometricEnabled = prefs.getBool('sko_secondary_biometric_enabled_$actor') ?? false;
    } catch (_) { /* Unknown stays unknown. */ }
    try {
      final availability = biometricAvailability;
      if (availability != null) {
        biometricAvailable = await availability().timeout(const Duration(seconds: 5));
      } else {
        final local = LocalAuthentication();
        // Hardware support alone does not establish enrolled Face ID / Touch ID.
        // Read capability and enrollment only; never invoke authentication here.
        final supported = await local.isDeviceSupported()
            .timeout(const Duration(seconds: 5)) &&
            await local.canCheckBiometrics.timeout(const Duration(seconds: 5));
        biometricAvailable = supported &&
            (await local.getAvailableBiometrics()
                .timeout(const Duration(seconds: 5))).isNotEmpty;
      }
    } catch (_) { /* No hardware verification claim on plugin failure. */ }
    if (!unchanged()) throw StateError('account_session_changed');
    final providers = (user.identities ?? <UserIdentity>[])
        .map((identity) => identity.provider).toSet().toList()..sort();
    final methods = <String>{};
    try {
      // Parse only after the exact JWT was validated with getUser above.
      final payload = jsonDecode(utf8.decode(
          base64Url.decode(base64Url.normalize(token.split('.')[1]))));
      if (payload is Map && payload['amr'] is List) {
        for (final value in payload['amr'] as List) {
          if (value is Map && value['method'] is String) {
            final method = value['method'] as String;
            if (const {'password', 'oauth', 'otp', 'totp', 'sso/saml'}
                .contains(method)) {
              methods.add(method);
            }
          }
        }
      }
    } catch (_) {
      // No guessing from linked providers when session evidence is unavailable.
    }
    return PanelSevenSnapshot(
      actorId: actor,
      providers: List.unmodifiable(providers),
      email: user.email,
      phone: user.phone,
      emailConfirmed: json['email_confirmed_at'] != null,
      phoneConfirmed: json['phone_confirmed_at'] != null,
      sessionMethods: List.unmodifiable(methods.toList()..sort()),
      secondaryConfigured: secondary,
      biometricEnabled: biometricEnabled,
      biometricAvailable: biometricAvailable,
      accessToken: token,
    );
  }
}

