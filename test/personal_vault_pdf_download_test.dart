import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sk_works/features/personal_vault/personal_vault_pdf_download.dart';

class _Client extends http.BaseClient {
  _Client(this.respond);
  final Future<http.StreamedResponse> Function(http.BaseRequest) respond;
  int closed = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => respond(request);
  @override
  void close() { closed++; }
}

void main() {
  final pdf = utf8.encode('%PDF-1.7\nfixture');
  final hash = sha256.convert(pdf).toString();
  final uri = Uri.parse('https://vault-fixture.invalid/storage/v1/object/personal-pdf-vault/personal-vault/owner/hash.pdf');
  late Completer<void> invalidated;
  late _Client client;
  late StreamController<List<int>> body;
  late int canceled, checked, sent;
  late Map<String, String> headers;
  late int status;
  late Map<String, String> responseHeaders;
  late int? contentLength;
  late Future<http.StreamedResponse> Function(http.BaseRequest)? beforeResponse;
  setUp(() {
    invalidated = Completer<void>(); canceled = checked = sent = 0;
    headers = {'Authorization':'Bearer fixture-only','apikey':'fixture-public',
      'aCcEpT-EnCoDiNg':'gzip'};
    status = 200; responseHeaders = {'content-type':'application/pdf'}; contentLength = null;
    beforeResponse = null;
    body = StreamController<List<int>>(onCancel: () { canceled++; });
    client = _Client((request) async {
      sent++;
      expect(request.method, 'GET'); expect(request.url, uri);
      expect(request.followRedirects, isFalse);
      expect(request.headers['Accept-Encoding'], 'identity');
      expect(request.headers.keys.where((name) => name.toLowerCase() == 'accept-encoding').length, 1);
      expect(request.headers['Authorization'], 'Bearer fixture-only');
      if (beforeResponse != null) { return beforeResponse!(request); }
      return http.StreamedResponse(body.stream, status,
        contentLength:contentLength, headers:responseHeaders, request:request);
    });
  });
  // Do not await close on an intentionally never-listened fixture stream.
  tearDown(() { unawaited(body.close()); });
  Future<Uint8List> download({Duration deadline = const Duration(seconds:5),
    int? expectedLength, String? expectedHash}) => PersonalVaultPdfDownload(
      clientFactory:() => client, deadline:deadline).download(uri:uri, headers:headers,
      expectedLength:expectedLength ?? pdf.length, expectedHash:expectedHash ?? hash,
      invalidated:invalidated.future, validateSession:() async { checked++; });
  Future<void> started() async {
    // Let the mock send and response subscription be established.
    await Future<void>.delayed(Duration.zero);
  }
  test('exact bytes are bound to captured authorization, receipt length and hash', () async {
    final result = download();
    headers['Authorization'] = 'Bearer replacement';
    await started(); body.add(pdf.sublist(0,5)); body.add(pdf.sublist(5));
    await body.close();
    expect(await result, pdf); expect(sent,1); expect(checked,2); expect(client.closed,greaterThan(0));
  });
  test('oversize chunk cancels before waiting for EOF or accepting partial bytes', () async {
    final result = download(); final assertion = expectLater(result,throwsStateError);
    await started(); body.add([...pdf,0]);
    await assertion; expect(canceled,1); expect(client.closed,greaterThan(0));
  });
  test('cumulative overflow cancels even when each chunk fits separately', () async {
    final assertion = expectLater(download(),throwsStateError);
    await started(); body.add(pdf.sublist(0,5)); body.add(pdf);
    await assertion; expect(canceled,1);
  });
  test('truncated and wrong-hash PDFs never return bytes', () async {
    final assertion = expectLater(download(),throwsStateError);
    await started(); body.add(pdf.sublist(1)); await body.close(); await assertion;
  });
  test('same length different bytes fail the saved hash', () async {
    final assertion = expectLater(download(),throwsStateError);
    await started(); body.add(List<int>.filled(pdf.length,0)); await body.close(); await assertion;
  });
  for (final code in [302,403]) {
    test('HTTP $code rejects without collecting its body or following a location', () async {
      status = code; responseHeaders['location'] = 'https://foreign.invalid/leak';
      final assertion = expectLater(download(),throwsStateError);
      await assertion; expect(canceled,1); expect(sent,1);
    });
  }
  test('wrong declared length is rejected and stream canceled before body data', () async {
    contentLength = pdf.length+1;
    await expectLater(download(),throwsStateError); expect(canceled,1);
  });
  test('compressed and non-PDF representations are refused before body data', () async {
    responseHeaders['content-encoding'] = 'gzip';
    await expectLater(download(),throwsStateError); expect(canceled,1);
  });
  test('HTTP header wait has an absolute deadline and a late body is canceled', () async {
    final lateResponse = Completer<http.StreamedResponse>();
    beforeResponse = (_) => lateResponse.future;
    await expectLater(download(deadline:const Duration(milliseconds:20)),throwsStateError);
    expect(client.closed,greaterThan(0));
    lateResponse.complete(http.StreamedResponse(body.stream,200,headers:responseHeaders));
    await started(); expect(canceled,1);
  });
  test('a body which never ends times out and cancels its subscription', () async {
    final assertion = expectLater(download(deadline:const Duration(milliseconds:20)),throwsStateError);
    await started(); body.add(pdf.sublist(0,2));
    await assertion; expect(canceled,1);
  });
  test('Auth invalidation cancels a stalled body with no further chunks', () async {
    final assertion = expectLater(download(),throwsStateError);
    await started(); invalidated.complete();
    await assertion; expect(canceled,1); expect(client.closed,greaterThan(0));
  });
  test('network errors are generic and cancel the dedicated client', () async {
    final assertion = expectLater(download(),throwsStateError);
    await started(); body.addError(StateError('fixture-sensitive-error'));
    await assertion; expect(client.closed,greaterThan(0));
  });
  test('invalid receipt size is refused before an HTTP request is sent', () async {
    await expectLater(download(expectedLength:PersonalVaultPdfDownload.maxBytes+1),throwsStateError);
    expect(sent,0);
  });
}
