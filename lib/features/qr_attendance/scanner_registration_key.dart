import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Public metadata only. Native Keychain keeps the signing key; this is no
/// registration/permission attestation and never substitutes for server checks.
class ScannerRegistrationKey {
  const ScannerRegistrationKey({required this.actor, required this.company,
    required this.device, required this.handle, required this.publicKeyHex});
  final String actor, company, device, handle, publicKeyHex;
}

/// OFF and unexposed: no route, registration request, password or key export.
class ScannerRegistrationKeyCustody with WidgetsBindingObserver {
  ScannerRegistrationKeyCustody(this.client, {
    this.enabled = const bool.fromEnvironment('SKO_QR_SCANNER_KEY_PREPARATION', defaultValue: false),
    this.channel = const MethodChannel('com.skworks.sko/qr_scanner_key'),
    Stream<AuthState>? authChanges,
  }) : _authChanges = authChanges;
  final SupabaseClient client;
  final bool enabled;
  final MethodChannel channel;
  final Stream<AuthState>? _authChanges;
  static final _uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
  static final _key = RegExp(r'^302a300506032b6570032100[0-9a-f]{64}$');
  bool _busy = false, _disposed = false;
  VoidCallback? _invalidate;
  static StateError _denied() => StateError('スキャナー鍵の確認を完了できません。');
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _invalidate?.call();
  }
  void dispose() { _disposed = true; _invalidate?.call(); }
  String _requestId() {
    final bytes = List.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64; bytes[8] = (bytes[8] & 63) | 128;
    final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0,8)}-${h.substring(8,12)}-${h.substring(12,16)}-${h.substring(16,20)}-${h.substring(20)}';
  }
  Future<({Map<String, dynamic> value, String token, String actor})> _call(String method, String company, String device,
      Map<String, dynamic> Function(String actor, String sid) extras) async {
    if (!enabled || _busy || _disposed || !_uuid.hasMatch(company) || !_uuid.hasMatch(device)) throw _denied();
    final captured = client.auth.currentSession;
    if (captured == null) throw _denied();
    final actor = captured.user.id, token = captured.accessToken;
    String sid;
    try {
      final claims = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[1])))) as Map<String, dynamic>;
      sid = claims['session_id'] as String;
      if (!_uuid.hasMatch(actor) || !_uuid.hasMatch(sid) || claims['sub'] != actor || claims['is_anonymous'] == true) throw _denied();
    } catch (_) { throw _denied(); }
    _busy = true;
    final requestId = _requestId();
    var invalid = false, nativeStarted = false, firstInitial = true;
    void invalidate() {
      if (invalid) return;
      invalid = true;
      if (nativeStarted) unawaited(channel.invokeMethod<void>('cancel', {'requestId': requestId}).catchError((Object _) {}));
    }
    _invalidate = invalidate;
    void live() {
      final current = client.auth.currentSession;
      if (invalid || _disposed || current?.user.id != actor || current?.accessToken != token) throw _denied();
    }
    final subscription = (_authChanges ?? client.auth.onAuthStateChange).listen((state) {
      if (firstInitial && state.event == AuthChangeEvent.initialSession && state.session?.user.id == actor && state.session?.accessToken == token) {
        firstInitial = false; return;
      }
      firstInitial = false; invalidate();
    }, onError: (Object _) => invalidate(), onDone: invalidate);
    WidgetsBinding.instance.addObserver(this);
    try {
      // Authoritative Auth user lookup precedes any local key operation. The
      // server independently validates the SID, company, permission and QR gate.
      final user = await client.auth.getUser(token);
      live();
      if (user.user?.id != actor || user.user?.isAnonymous != false) throw _denied();
      final args = <String, dynamic>{'requestId': requestId, 'actor': actor, 'company': company, 'device': device, ...extras(actor, sid)};
      live(); nativeStarted = true;
      final value = await channel.invokeMapMethod<String, dynamic>(method, args).timeout(const Duration(seconds: 95));
      live();
      if (value == null) throw _denied();
      return (value: Map<String, dynamic>.from(value), token: token, actor: actor);
    } catch (_) { invalidate(); throw _denied(); }
    finally {
      WidgetsBinding.instance.removeObserver(this); await subscription.cancel();
      if (_invalidate == invalidate) _invalidate = null;
      _busy = false;
    }
  }
  Future<ScannerRegistrationKey> prepare({required String company, required String device}) async {
    final result = await _call('prepare', company, device, (_, _) => {});
    final value = result.value;
    final expectedHandle = sha256.convert(utf8.encode('sko.qr.scanner.custody.v1\n${result.actor}\n$company\n$device')).toString();
    if (_disposed || client.auth.currentSession?.accessToken != result.token || value['handle'] != expectedHandle) throw _denied();
    if (value.length != 2 || value['handle'] is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(value['handle'] as String) ||
        value['publicKeyHex'] is! String || !_key.hasMatch(value['publicKeyHex'] as String)) throw _denied();
    return ScannerRegistrationKey(actor: result.actor, company: company, device: device, handle: value['handle'] as String, publicKeyHex: value['publicKeyHex'] as String);
  }
  Future<String> signRegistration({required ScannerRegistrationKey key, required Map<String, dynamic> challenge}) async {
    // Snapshot scalar challenge data before any Auth/network/native await.
    final snapshot = Map<String, dynamic>.unmodifiable(Map<String, dynamic>.from(challenge));
    final result = await _call('sign', key.company, key.device, (actor, sid) {
      if (actor != key.actor || snapshot['actor'] != actor || snapshot['session'] != sid || snapshot['company'] != key.company ||
          snapshot['device'] != key.device || snapshot['keyHex'] != key.publicKeyHex) throw _denied();
      return {'session': sid, 'handle': key.handle, 'challenge': snapshot};
    });
    final value = result.value;
    if (_disposed || client.auth.currentSession?.accessToken != result.token) throw _denied();
    final signature = value['signature'];
    if (value.length != 2 || value['handle'] != key.handle || signature is! String || !RegExp(r'^[A-Za-z0-9_-]{86}$').hasMatch(signature) ||
        base64Url.encode(base64Url.decode(base64Url.normalize(signature))).replaceAll('=', '') != signature) throw _denied();
    return signature;
  }
}
