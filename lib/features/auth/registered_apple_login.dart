import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import 'app_auth_mutation_gateway.dart';
import 'apple_session_navigation_binding.dart';

class AppleRegistrationProbeResult implements Exception {
  const AppleRegistrationProbeResult(this.message);
  final String message;
}

class RegisteredAppleLogin {
  static const registrationProbe =
      bool.fromEnvironment('SKO_APPLE_REGISTRATION_PROBE');
  static const _gatewayAnonJwt =
      String.fromEnvironment('SKO_APPLE_LOGIN_GATEWAY_ANON_JWT');
  const RegisteredAppleLogin._();

  static bool get available =>
      const bool.fromEnvironment('SKO_REGISTERED_APPLE_LOGIN_ENABLED') &&
      (registrationProbe || _gatewayAnonJwt.isNotEmpty) &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.iOS &&
      SupabaseBackend.isInitialized &&
      SupabaseBackendConfig.url == 'https://ztktgquxvcxcjxtluspu.supabase.co';

  static Future<void> _recordProbe(String stage) async {
    if (!registrationProbe) return;
    const channel = MethodChannel('com.skworks.sko/apple_credential');
    try {
      await channel.invokeMethod<bool>('recordAppleProbe', stage)
          .timeout(const Duration(seconds: 3));
    } on Exception {
      throw const AppleRegistrationProbeResult('iPadに診断を保存できませんでした');
    }
  }

  static Future<void> signIn({required bool Function() isCurrent}) async {
    await _recordProbe('started');
    if (!available) throw StateError('Appleログインは準備中です。');
    final client = SupabaseBackend.client;
    if (client.auth.currentSession != null) {
      throw StateError('現在のログインを使用してください。');
    }
    var sessionChanged = false;
    var drainingReplay = true;
    var replayCount = 0;
    final subscription = client.auth.onAuthStateChange.listen(
      (event) {
        // GoTrue replays its last event when a listener attaches. A queued
        // signed-out baseline is not a session change during Apple sign-in.
        if (drainingReplay && ++replayCount == 1 &&
            event.session == null && client.auth.currentSession == null &&
            (event.event == AuthChangeEvent.initialSession ||
                event.event == AuthChangeEvent.signedOut)) {
          return;
        }
        if (event.session != null || event.event == AuthChangeEvent.signedOut) {
          sessionChanged = true;
        }
      },
      onError: (Object _) => sessionChanged = true,
      onDone: () => sessionChanged = true,
    );
    void check() {
      if (!isCurrent() ||
          sessionChanged ||
          client.auth.currentSession != null) {
        throw StateError('ログイン状態が変わりました。');
      }
    }

    const channel = MethodChannel('com.skworks.sko/apple_credential');
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final transport = http.Client();
    var stage = '端末での本人確認';
    try {
      await Future<void>.value();
      drainingReplay = false;
      check();
      await _recordProbe('native_request');
      final raw = await channel
          .invokeMapMethod<String, Object?>('requestAppleCredential', {
            'request_id': id,
          })
          .timeout(const Duration(minutes: 3));
      await _recordProbe('native_returned');
      stage = '本人確認後の画面・セッション照合';
      check();
      stage = 'Apple認証情報の確認';
      final token = raw?['id_token'];
      final nonce = raw?['nonce'];
      if (token is! String ||
          token.length > 16384 ||
          token.split('.').length != 3 ||
          nonce is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{43,128}$').hasMatch(nonce)) {
        throw StateError('Appleの本人確認を完了できませんでした。');
      }
      final endpoint = Uri.parse(
        registrationProbe
            ? '${SupabaseBackendConfig.url}/auth/v1/token?grant_type=id_token'
            : '${SupabaseBackendConfig.url}/functions/v1/apple-existing-login',
      );
      final request = http.Request('POST', endpoint)
        ..followRedirects = false
        ..headers.addAll({
          'apikey': SupabaseBackendConfig.publishableKey,
          if (!registrationProbe) 'authorization': 'Bearer $_gatewayAnonJwt',
          'content-type': 'application/json',
        })
        ..body = jsonEncode({
          if (registrationProbe) 'provider': 'apple',
          'id_token': token,
          'nonce': nonce,
        });
      stage = '本番認証APIへの送信';
      await _recordProbe('auth_request');
      check();
      final response = await transport
          .send(request)
          .timeout(const Duration(seconds: 20));
      if (registrationProbe) {
        await _recordProbe('http_${response.statusCode}');
        throw AppleRegistrationProbeResult('HTTP ${response.statusCode}');
      }
      if (response.statusCode != 200) throw StateError('Appleログインを確認できませんでした。');
      final bytes = await response.stream
          .fold<List<int>>(<int>[], (buffer, chunk) {
            if (buffer.length + chunk.length > 65536) {
              throw StateError('Appleログインを確認できませんでした。');
            }
            return buffer..addAll(chunk);
          })
          .timeout(const Duration(seconds: 10));
      final body = utf8.decode(bytes);
      check();
      final session = Session.fromJson(
        jsonDecode(body) as Map<String, dynamic>,
      );
      if (session == null ||
          session.refreshToken?.isNotEmpty != true ||
          session.isExpired ||
          AppleSessionNavigationBinding.fromSession(session) == null) {
        throw StateError('既存のSKOアカウントを確認できませんでした。');
      }
      final verified =
          (await client.auth
                  .getUser(session.accessToken)
                  .timeout(const Duration(seconds: 10)))
              .user;
      check();
      if (verified == null ||
          verified.id != session.user.id ||
          verified.isAnonymous ||
          verified.identities?.any(
                (identity) =>
                    identity.provider == 'apple' &&
                    identity.userId == verified.id,
              ) !=
              true) {
        throw StateError('既存のSKOアカウントを確認できませんでした。');
      }
      await AppAuthMutationGateway.forClient(
        client,
      ).adoptRegisteredAppleSession(
        session,
        isCurrent: () => isCurrent() && !sessionChanged,
      );
    } on AppleRegistrationProbeResult {
      rethrow;
    } catch (_) {
      if (registrationProbe) {
        await _recordProbe('stopped');
        throw AppleRegistrationProbeResult('$stage で停止しました');
      }
      rethrow;
    } finally {
      transport.close();
      await subscription.cancel();
      try {
        await channel
            .invokeMethod<Object?>('cancelAppleCredential', {'request_id': id})
            .timeout(const Duration(seconds: 2));
      } catch (_) {
        // A finished or unavailable native request needs no cleanup.
      }
    }
  }
}
