import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Unexposed candidate transport. Owns its HTTP client so cancellation never
/// closes the application's shared Auth/PostgREST client. Never follows a URL
/// returned in a response or buffers an error body.
class PersonalVaultPdfDownload {
  PersonalVaultPdfDownload({http.Client Function()? clientFactory,
    this.deadline = const Duration(seconds: 30)})
      : _clientFactory = clientFactory ?? http.Client.new;

  static const maxBytes = 50 * 1024 * 1024;
  final http.Client Function() _clientFactory;
  final Duration deadline;
  static StateError _failure() => StateError('本人PDFの取得を完了できませんでした。');

  Future<Uint8List> download({required Uri uri,
    required Map<String, String> headers, required int expectedLength,
    required String expectedHash, required Future<void> invalidated,
    required Future<void> Function() validateSession}) async {
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty ||
        uri.hasQuery || uri.hasFragment || expectedLength < 1 ||
        expectedLength > maxBytes || !RegExp(r'^[a-f0-9]{64}$').hasMatch(expectedHash) ||
        deadline <= Duration.zero) { throw _failure(); }
    // Snapshot before any asynchronous operation; caller changes cannot replace
    // the request authorization or expected receipt while bytes are arriving.
    final requestHeaders = Map<String, String>.from(headers)
      ..removeWhere((name, _) => name.toLowerCase() == 'accept-encoding')
      ..['Accept-Encoding'] = 'identity';
    final client = _clientFactory();
    final result = Completer<Uint8List>();
    StreamSubscription<List<int>>? subscription;
    void fail() {
      if (result.isCompleted) { return; }
      result.completeError(_failure());
      client.close();
      final current = subscription;
      if (current != null) { unawaited(current.cancel().catchError((Object _) {})); }
    }
    // Timer callbacks may be delayed by synchronous Auth/body work. Measure the
    // elapsed budget as well, so an overdue response cannot win that race.
    final elapsed = Stopwatch()..start();
    bool active() {
      if (elapsed.elapsed >= deadline) { fail(); }
      return !result.isCompleted;
    }
    final timer = Timer(deadline, fail);
    unawaited(invalidated.then((_) { fail(); }, onError: (Object _) { fail(); }));
    unawaited(() async {
      try {
        await validateSession();
        if (!active()) { return; }
        final request = http.Request('GET', uri)
          ..followRedirects = false
          ..headers.addAll(requestHeaders);
        final response = await client.send(request);
        if (!active()) {
          unawaited(response.stream.listen(null, onError: (Object _) {}).cancel().catchError((Object _) {}));
          return;
        }
        final encoding = response.headers['content-encoding'];
        if (response.statusCode != 200 || response.isRedirect ||
            response.headers['content-type']?.split(';').first.trim().toLowerCase() != 'application/pdf' ||
            encoding != null && encoding.toLowerCase() != 'identity' ||
            response.contentLength != null && response.contentLength != expectedLength) {
          // Cancel even a non-200 or oversized stream without reading its body.
          subscription = response.stream.listen(null, onError: (Object _) {});
          fail();
          return;
        }
        final bytes = BytesBuilder(copy: true);
        var length = 0;
        subscription = response.stream.listen((chunk) {
          if (!active()) { return; }
          if (chunk.length > expectedLength - length) { fail(); return; }
          length += chunk.length;
          bytes.add(chunk);
        }, onError: (Object _) { fail(); }, onDone: () async {
          if (!active()) { return; }
          try {
            if (length != expectedLength) { fail(); return; }
            final pdf = bytes.takeBytes();
            if (sha256.convert(pdf).toString() != expectedHash) { fail(); return; }
            await validateSession();
            if (active()) { result.complete(pdf); }
          } catch (_) { fail(); }
        }, cancelOnError: true);
      } catch (_) { fail(); }
    }());
    try { return await result.future; }
    finally {
      elapsed.stop();
      timer.cancel();
      client.close();
      final current = subscription;
      if (current != null) { unawaited(current.cancel().catchError((Object _) {})); }
    }
  }
}
