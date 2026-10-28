import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:sk_works/features/personal_vault/personal_vault_pdf_download.dart';

// Real loopback TLS with a per-suite ephemeral certificate. No badCertificateCallback,
// public network, production credentials or application-wide HttpOverrides.
void main() {
  late Directory fixture;
  late SecurityContext trusted;
  late HttpServer server;
  late Completer<void> invalidated;
  final pdf = utf8.encode('%PDF-1.7\nloopback fixture');
  final received = <String>[];
  setUpAll(() async {
    fixture = await Directory.systemTemp.createTemp('vault-tls-');
    final result = await Process.run('openssl', ['req','-x509','-newkey','rsa:2048',
      '-nodes','-keyout','${fixture.path}/key.pem','-out','${fixture.path}/cert.pem',
      '-days','1','-subj','/CN=localhost','-addext','subjectAltName=IP:127.0.0.1']);
    expect(result.exitCode, 0, reason: 'ephemeral TLS fixture generation');
    trusted = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificates('${fixture.path}/cert.pem');
  });
  tearDownAll(() async { await fixture.delete(recursive: true); });
  setUp(() async {
    final context = SecurityContext()
      ..useCertificateChain('${fixture.path}/cert.pem')
      ..usePrivateKey('${fixture.path}/key.pem');
    server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context);
    invalidated = Completer<void>(); received.clear();
  });
  tearDown(() async { await server.close(force: true); });
  Future<List<int>> download({Duration deadline = const Duration(seconds: 3),
    String? hash, int? length, IOClient? client}) {
    return PersonalVaultPdfDownload(deadline: deadline,
      clientFactory: () => client ?? IOClient(HttpClient(context: trusted)))
      .download(uri: Uri.parse('https://127.0.0.1:${server.port}/private.pdf'),
        headers: {'Authorization':'Bearer synthetic-captured'},
        expectedLength: length ?? pdf.length,
        expectedHash: hash ?? sha256.convert(pdf).toString(),
        invalidated: invalidated.future, validateSession: () async {});
  }
  void serve(Future<void> Function(HttpRequest) handle) {
    server.listen((request) async {
      received.add(request.headers.value(HttpHeaders.authorizationHeader) ?? '');
      try { await handle(request); } catch (_) { /* canceled socket */ }
    });
  }
  test('real TLS returns exact receipt bytes and captured bearer', () async {
    serve((request) async {
      request.response.headers.contentType = ContentType('application','pdf');
      request.response.contentLength = pdf.length;
      request.response.add(pdf); await request.response.close();
    });
    expect(await download(), pdf);
    expect(received, ['Bearer synthetic-captured']);
  });
  test('real TLS redirect is never followed', () async {
    serve((request) async {
      request.response.statusCode = 302;
      request.response.headers.set('location','https://127.0.0.1:${server.port}/leak');
      await request.response.close();
    });
    await expectLater(download(), throwsStateError);
    expect(received.length, 1);
  });
  test('real TLS rejects a wrong receipt hash', () async {
    serve((request) async {
      request.response.headers.contentType = ContentType('application','pdf');
      request.response.add(pdf); await request.response.close();
    });
    await expectLater(download(hash: '0' * 64), throwsStateError);
  });
  test('stalled response headers are bounded by absolute deadline', () async {
    final arrived = Completer<void>();
    serve((request) async { arrived.complete(); });
    final assertion = expectLater(download(deadline: const Duration(milliseconds: 400)), throwsStateError);
    await arrived.future.timeout(const Duration(seconds: 2));
    await assertion;
    expect(received.length, 1);
  });
  test('invalidation closes real stalled body without touching another client', () async {
    final started = Completer<void>();
    final other = IOClient(HttpClient(context: trusted));
    addTearDown(other.close);
    serve((request) async {
      request.response.headers.contentType = ContentType('application','pdf');
      if (request.uri.path == '/other') {
        request.response.add(pdf); await request.response.close(); return;
      }
      request.response.add(pdf.sublist(0, 4));
      await request.response.flush(); started.complete();
    });
    final assertion = expectLater(download(), throwsStateError);
    await started.future.timeout(const Duration(seconds: 2));
    invalidated.complete(); await assertion;
    final response = await other.get(Uri.parse('https://127.0.0.1:${server.port}/other'));
    expect(response.bodyBytes, pdf);
    expect(received.length, 2);
  });
  test('real chunked overflow rejects before server EOF', () async {
    final sent = Completer<void>();
    serve((request) async {
      request.response.headers.contentType = ContentType('application','pdf');
      request.response.add([...pdf, 0]);
      await request.response.flush(); sent.complete();
    });
    final assertion = expectLater(download(), throwsStateError);
    await sent.future.timeout(const Duration(seconds: 2)); await assertion;
  });
}
