import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:sk_works/features/personal_vault/personal_vault_pdf_download.dart';

// Native client only for this loopback fixture: no global override or bad cert callback.
class _NativeFixtureHttp extends HttpOverrides {}

class _DetachedConnection {
  _DetachedConnection(this.socket) {
    subscription = socket.listen((_) {}, onError:(Object _) {
      if (!peerClosed.isCompleted) { peerClosed.complete(); }
    }, onDone:() {
      if (!peerClosed.isCompleted) { peerClosed.complete(); }
    });
  }
  final Socket socket;
  final peerClosed = Completer<void>();
  late final StreamSubscription<List<int>> subscription;
}

// Detached TLS sockets remain open until the client closes or test teardown.
// Rejection tests must observe peer closure before releasing the server.
void main() {
  late Directory fixture;
  late SecurityContext trusted;
  late HttpServer server;
  late Completer<void> invalidated;
  final pdf = utf8.encode('%PDF-1.7\nloopback fixture');
  final received = <Map<String,String>>[];
  final detached = <_DetachedConnection>[];
  final releases = <Completer<void>>[];
  setUpAll(() async {
    fixture = await Directory.systemTemp.createTemp('vault-tls-');
    final result = await Process.run('openssl', ['req','-x509','-newkey','rsa:2048',
      '-nodes','-keyout','${fixture.path}/key.pem','-out','${fixture.path}/cert.pem',
      '-days','1','-subj','/CN=localhost','-addext','subjectAltName=IP:127.0.0.1']);
    expect(result.exitCode,0,reason:'ephemeral TLS fixture generation');
    trusted = SecurityContext(withTrustedRoots:false)
      ..setTrustedCertificates('${fixture.path}/cert.pem');
  });
  tearDownAll(() async { await fixture.delete(recursive:true); });
  setUp(() async {
    final context = SecurityContext()
      ..useCertificateChain('${fixture.path}/cert.pem')
      ..usePrivateKey('${fixture.path}/key.pem');
    server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4,0,context);
    invalidated = Completer<void>(); received.clear(); detached.clear(); releases.clear();
  });
  tearDown(() async {
    for (final release in releases) {
      if (!release.isCompleted) { release.complete(); }
    }
    // HttpServer no longer owns these sockets, so cleanup is explicit.
    for (final connection in detached) {
      connection.socket.destroy(); await connection.subscription.cancel();
    }
    await server.close(force:true);
  });
  IOClient client() => IOClient(_NativeFixtureHttp().createHttpClient(trusted));
  Future<List<int>> download({Duration deadline = const Duration(seconds:20),
    String? hash,int? length}) => PersonalVaultPdfDownload(deadline:deadline,clientFactory:client)
      .download(uri:Uri.parse('https://127.0.0.1:${server.port}/private.pdf'),
        headers:{'Authorization':'Bearer synthetic-captured'},expectedLength:length ?? pdf.length,
        expectedHash:hash ?? sha256.convert(pdf).toString(),invalidated:invalidated.future,
        validateSession:() async {});
  void serve(Future<void> Function(HttpRequest) handle) {
    server.listen((request) async {
      received.add({'method':request.method,'path':request.uri.path,
        'authorization':request.headers.value(HttpHeaders.authorizationHeader) ?? '',
        'encoding':request.headers.value(HttpHeaders.acceptEncodingHeader) ?? ''});
      try { await request.drain<void>(); await handle(request); }
      catch (_) { /* Expected disconnect; assertions are outside this catch. */ }
    });
  }
  Future<_DetachedConnection> detach(HttpRequest request) async {
    final connection = _DetachedConnection(await request.response.detachSocket(writeHeaders:false));
    detached.add(connection); return connection;
  }
  Completer<void> releaseGate() {
    final release = Completer<void>(); releases.add(release); return release;
  }
  Future<void> rejectedAndClosed(Future<void> assertion,
    _DetachedConnection connection,Completer<void> release) async {
    // Normal transport deadline is 20s. A timer-only rejection cannot pass the
    // shorter overflow/header/Auth observation bound below.
    await assertion.timeout(const Duration(seconds:5));
    await connection.peerClosed.future.timeout(const Duration(seconds:5));
    expect(release.isCompleted,isFalse,reason:'client must close before server EOF/release');
  }
  List<int> responseHead({String contentType='application/pdf',String? encoding,
    int? length,bool chunked=false}) => ascii.encode('HTTP/1.1 200 OK\r\n'
      'Content-Type: $contentType\r\n'
      '${encoding == null ? '' : 'Content-Encoding: $encoding\r\n'}'
      '${length == null ? '' : 'Content-Length: $length\r\n'}'
      '${chunked ? 'Transfer-Encoding: chunked\r\n' : ''}\r\n');

  test('real TLS exact bytes, captured bearer and identity encoding',() async {
    serve((request) async {
      request.response.headers.contentType=ContentType('application','pdf');
      request.response.contentLength=pdf.length;
      request.response.add(pdf);await request.response.close();
    });
    expect(await download(),pdf);
    expect(received,[{'method':'GET','path':'/private.pdf',
      'authorization':'Bearer synthetic-captured','encoding':'identity'}]);
  });
  test('real TLS redirect is never followed',() async {
    serve((request) async {
      request.response.statusCode=302;
      request.response.headers.set('location','https://127.0.0.1:${server.port}/leak');
      await request.response.close();
    });
    await expectLater(download(),throwsStateError);
    expect(received.map((row)=>row['path']),['/private.pdf']);
  });
  test('real TLS rejects same-length wrong receipt hash',() async {
    serve((request) async {
      request.response.headers.contentType=ContentType('application','pdf');
      request.response.contentLength=pdf.length;
      request.response.add(pdf);await request.response.close();
    });
    await expectLater(download(hash:'0'*64),throwsStateError);
  });
  for (final phase in ['headers','body']) {
    test('absolute deadline closes stalled $phase before server release',() async {
      final arrived=Completer<_DetachedConnection>(),release=releaseGate();
      serve((request) async {
        final connection=await detach(request);
        if (phase=='body') {
          connection.socket.add([...responseHead(length:pdf.length),...pdf.sublist(0,4)]);
          await connection.socket.flush();
        }
        arrived.complete(connection);await release.future;
      });
      final assertion=expectLater(download(deadline:const Duration(seconds:2)),throwsStateError);
      final connection=await arrived.future.timeout(const Duration(seconds:5));
      await rejectedAndClosed(assertion,connection,release);expect(received.length,1);
    });
  }
  test('Auth invalidation closes stalled body and preserves another client',() async {
    final started=Completer<_DetachedConnection>(),release=releaseGate();
    final other=client();addTearDown(other.close);
    serve((request) async {
      if (request.uri.path=='/other') {
        request.response.headers.contentType=ContentType('application','pdf');
        request.response.add(pdf);await request.response.close();return;
      }
      final connection=await detach(request);
      connection.socket.add([...responseHead(length:pdf.length),...pdf.sublist(0,4)]);
      await connection.socket.flush();started.complete(connection);await release.future;
    });
    var settled=false;
    final pending=download();
    unawaited(pending.then((_) { settled=true; },onError:(Object _) { settled=true; }));
    final assertion=expectLater(pending,throwsStateError);
    final connection=await started.future.timeout(const Duration(seconds:5));
    await Future<void>.delayed(Duration.zero);
    expect(settled,isFalse,reason:'valid partial body must still be pending before invalidation');
    invalidated.complete();await rejectedAndClosed(assertion,connection,release);
    final response=await other.get(Uri.parse('https://127.0.0.1:${server.port}/other'));
    expect(response.bodyBytes,pdf);expect(received.length,2);
  });
  test('chunked overflow closes before server EOF and before long deadline',() async {
    final started=Completer<_DetachedConnection>(),release=releaseGate();
    serve((request) async {
      final connection=await detach(request);
      // A complete 64KiB chunk exceeds the receipt; a following partial chunk
      // keeps HTTP unfinished. Size exceeds native buffering, unlike tiny data.
      final excess=List<int>.filled(64*1024,65);
      connection.socket.add([...responseHead(chunked:true),
        ...ascii.encode('${excess.length.toRadixString(16)}\r\n'),...excess,
        ...ascii.encode('\r\n1\r\n')]);
      try { await connection.socket.flush(); }
      finally { started.complete(connection); }
      await release.future;
    });
    final assertion=expectLater(download(),throwsStateError);
    final connection=await started.future.timeout(const Duration(seconds:5));
    await rejectedAndClosed(assertion,connection,release);
  });
  for (final variant in ['declared-size','gzip','non-pdf']) {
    test('real TLS $variant closes without waiting for body',() async {
      final started=Completer<_DetachedConnection>(),release=releaseGate();
      serve((request) async {
        final connection=await detach(request);
        connection.socket.add(responseHead(
          length:variant=='declared-size' ? PersonalVaultPdfDownload.maxBytes+1 : pdf.length,
          encoding:variant=='gzip' ? 'gzip' : null,
          contentType:variant=='non-pdf' ? 'application/json' : 'application/pdf'));
        try { await connection.socket.flush(); }
        finally { started.complete(connection); }
        await release.future;
      });
      final assertion=expectLater(download(),throwsStateError);
      final connection=await started.future.timeout(const Duration(seconds:5));
      await rejectedAndClosed(assertion,connection,release);
      expect(received.single['encoding'],'identity');
    });
  }
}
