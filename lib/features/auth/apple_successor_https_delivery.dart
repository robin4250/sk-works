import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Internal, one-attempt delivery to an application-configured HTTPS endpoint.
/// This is not a public endpoint, session adoption, or an acknowledgement that
/// the server completed enrollment. A failed/unknown response is never retried.
class AppleSuccessorHttpsDelivery {
  AppleSuccessorHttpsDelivery({required this.endpoint,
    this.enabled = false,
    this.deadline = const Duration(seconds: 30),
    HttpClient Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? HttpClient.new;

  final Uri endpoint;
  final bool enabled;
  final Duration deadline;
  final HttpClient Function() _clientFactory;
  bool _attempted = false, _cancelled = false;
  void Function()? _abortActive;
  static const maxResponseBytes = 49152;
  static final _uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');
  static StateError _failure() => StateError('Apple連携の応答を確認できませんでした。再送せずログイン状態を確認してください。');

  /// Terminal local cancellation. It closes the owned socket but cannot undo
  /// server work already received. Never retry or infer enrollment rollback.
  void cancel() {
    _cancelled = true;
    _abortActive?.call();
  }

  Future<Map<String, dynamic>> receiveOnce({required String bearer,
    required String requestId, required String actor,
    required String password, required String idToken, required String rawNonce}) async {
    if (_attempted || _cancelled || !enabled || kIsWeb) { throw _failure(); }
    _attempted = true;
    if (endpoint.scheme != 'https' || endpoint.host.isEmpty || endpoint.userInfo.isNotEmpty ||
        endpoint.hasQuery || endpoint.hasFragment || endpoint.path.isEmpty ||
        endpoint.path == '/' || endpoint.normalizePath().path != endpoint.path ||
        bearer.isEmpty || bearer.length > 16384 || RegExp(r'\s').hasMatch(bearer) ||
        !_uuid.hasMatch(requestId) || !_uuid.hasMatch(actor) ||
        password.isEmpty || password.length > 1024 || idToken.isEmpty || idToken.length > 16384 ||
        !RegExp(r'^[A-Za-z0-9_-]{43,128}$').hasMatch(rawNonce) ||
        deadline <= Duration.zero || deadline > const Duration(minutes: 3)) { throw _failure(); }
    final body = utf8.encode(jsonEncode({'password': password, 'id_token': idToken, 'nonce': rawNonce}));
    if (body.length > 32768) { throw _failure(); }
    late final HttpClient client;
    try { client = _clientFactory(); } catch (_) { throw _failure(); }
    HttpClientRequest? request;
    var terminal = false;
    void abort() {
      terminal = true;
      request?.abort(_failure());
      client.close(force: true);
    }
    _abortActive = abort;
    void check() { if (terminal || _cancelled) { throw _failure(); } }
    Future<Map<String, dynamic>> send() async {
      check();
      request = await client.postUrl(endpoint);
      check();
      final outgoing = request!;
      outgoing.followRedirects = false;
      outgoing.maxRedirects = 0;
      outgoing.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
      outgoing.headers.contentType = ContentType.json;
      outgoing.headers.set(HttpHeaders.acceptHeader, 'application/json');
      outgoing.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      outgoing.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      outgoing.headers.set('x-sko-request-id', requestId);
      outgoing.contentLength = body.length;
      outgoing.add(body);
      final response = await outgoing.close();
      check();
      final type = response.headers.contentType;
      final charset = type?.charset;
      final encoding = response.headers.value(HttpHeaders.contentEncodingHeader);
      final cache = response.headers.value(HttpHeaders.cacheControlHeader) ?? '';
      if (response.statusCode != 200 || response.isRedirect || response.redirects.isNotEmpty ||
          response.headers.value(HttpHeaders.locationHeader) != null ||
          type?.mimeType.toLowerCase() != 'application/json' ||
          charset != null && charset.toLowerCase() != 'utf-8' ||
          encoding != null && encoding.toLowerCase() != 'identity' ||
          !cache.toLowerCase().split(',').any((part) => part.trim() == 'no-store') ||
          response.contentLength > maxResponseBytes) { throw _failure(); }
      final bytes = <int>[];
      await for (final chunk in response) {
        check();
        if (chunk.length > maxResponseBytes - bytes.length) { throw _failure(); }
        bytes.addAll(chunk);
      }
      check();
      if (bytes.isEmpty || response.contentLength >= 0 && bytes.length != response.contentLength) { throw _failure(); }
      final raw = jsonDecode(utf8.decode(bytes, allowMalformed: false));
      const fields = {'schema', 'request_id', 'user_id', 'session_id', 'token_type', 'access_token', 'refresh_token'};
      if (raw is! Map<String, dynamic> || raw.length != fields.length ||
          raw.keys.any((key) => !fields.contains(key)) || raw['schema'] != 1 ||
          raw['request_id'] != requestId || raw['user_id'] != actor || raw['token_type'] != 'bearer' ||
          raw['session_id'] is! String || !_uuid.hasMatch(raw['session_id'] as String) ||
          ['access_token', 'refresh_token'].any((key) => raw[key] is! String ||
            (raw[key] as String).isEmpty || (raw[key] as String).length > 16384)) { throw _failure(); }
      return Map<String, dynamic>.unmodifiable(raw);
    }
    try {
      client.autoUncompress = false;
      client.connectionTimeout = deadline;
      return await send().timeout(deadline, onTimeout: () {
        abort();
        throw _failure();
      });
    } catch (_) {
      throw _failure();
    } finally {
      terminal = true;
      _abortActive = null;
      request?.abort();
      client.close(force: true);
    }
  }
}
