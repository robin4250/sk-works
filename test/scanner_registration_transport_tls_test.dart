import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http/testing.dart';
import 'package:sk_works/features/qr_attendance/scanner_registration_key.dart';
import 'package:sk_works/features/qr_attendance/scanner_registration_transport.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'scanner_registration_flow_test.dart' as fixture;

class _NativeFixtureHttp extends HttpOverrides {}
class _LateHeaders extends http.BaseClient {
 final started=Completer<void>(),response=Completer<http.StreamedResponse>();
 @override Future<http.StreamedResponse> send(http.BaseRequest request){started.complete();return response.future;}
}
// Delivers headers, then retires the owner immediately after the await
// continuation acquires them, before the outer wait performs its live check.
class _RetiringFuture implements Future<http.StreamedResponse> {
 _RetiringFuture(this.base,this.retire);final Future<http.StreamedResponse> base;final void Function() retire;
 @override Future<R> then<R>(FutureOr<R> Function(http.StreamedResponse) onValue,{Function? onError})=>base.then<R>((value){final result=onValue(value);retire();return result;},onError:onError);
 @override Future<http.StreamedResponse> catchError(Function onError,{bool Function(Object)? test})=>base.catchError(onError,test:test);
 @override Future<http.StreamedResponse> whenComplete(FutureOr<void> Function() action)=>base.whenComplete(action);
 @override Future<http.StreamedResponse> timeout(Duration timeLimit,{FutureOr<http.StreamedResponse> Function()? onTimeout})=>base.timeout(timeLimit,onTimeout:onTimeout);
 @override Stream<http.StreamedResponse> asStream()=>base.asStream();
}
class _RetiringHeaders extends http.BaseClient {
 _RetiringHeaders(this.response,this.retire);final http.StreamedResponse response;final void Function() retire;
 @override Future<http.StreamedResponse> send(http.BaseRequest request)=>_RetiringFuture(Future.value(response),retire);
}
class _Tls {
 late Directory directory;late HttpServer server;late IOClient httpClient;late SupabaseClient auth;
 late ScannerRegistrationSession owner;late ScannerRegistrationTransport transport;
 final closed=Completer<void>();final sockets=<Socket>[];int requests=0;Object? fixtureFailure;
 Future<void> open(Future<void> Function(HttpRequest request,Map<String,dynamic> body) handle) async {
  directory=await Directory.systemTemp.createTemp('qr-registration-tls-');
  final cert=File('${directory.path}/cert.pem'),key=File('${directory.path}/key.pem');
  final generated=await Process.run('openssl',['req','-x509','-newkey','rsa:2048','-nodes','-keyout',key.path,'-out',cert.path,'-days','1','-subj','/CN=localhost','-addext','subjectAltName=DNS:localhost,IP:127.0.0.1']);
  if(generated.exitCode!=0)throw StateError('ephemeral TLS fixture unavailable');
  final context=SecurityContext()..useCertificateChain(cert.path)..usePrivateKey(key.path);
  server=await HttpServer.bindSecure(InternetAddress.loopbackIPv4,0,context);
  server.listen((request) async {
   requests++;
   try{
    expect(request.method,'POST');expect(request.uri.path,'/qr/scanner/registration');expect(request.headers.value('authorization'),'Bearer ${jsonDecode(fixture.sdkSession())['access_token']}');
    final body=jsonDecode(await utf8.decoder.bind(request).join()) as Map<String,dynamic>;
    await handle(request,body);
   }catch(error){if(error is TestFailure)fixtureFailure=error;try{await request.response.close();}catch(_){}}
  });
  final trusted=SecurityContext(withTrustedRoots:false)..setTrustedCertificates(cert.path);
  httpClient=IOClient(_NativeFixtureHttp().createHttpClient(trusted));
  auth=SupabaseClient('https://qr-auth-fixture.invalid','synthetic-public',authOptions:const AuthClientOptions(autoRefreshToken:false),httpClient:MockClient((r) async {
   expect(r.url.origin,'https://qr-auth-fixture.invalid');expect(r.url.path,'/auth/v1/user');expect(r.url.query,isEmpty);
   return http.Response(jsonEncode((jsonDecode(fixture.sdkSession()) as Map)['user']),200,headers:{'content-type':'application/json'});
  }));await auth.auth.setInitialSession(fixture.sdkSession());owner=ScannerRegistrationSession(auth);
  transport=ScannerRegistrationTransport.forTesting(origin:Uri(scheme:'https',host:'127.0.0.1',port:server.port),client:httpClient,enabled:true);
 }
 Future<void> stall(HttpRequest request) async {
  final chunked=request.response.contentLength<0;
  if(chunked)request.response.headers.set(HttpHeaders.transferEncodingHeader,'chunked');
  final socket=await request.response.detachSocket(writeHeaders:true);sockets.add(socket);
  // Observe actual peer socket shutdown, not HttpResponse.done (which is not
  // a peer-close signal and may settle merely because the response detached).
  socket.listen((_) {},onDone:(){if(!closed.isCompleted)closed.complete();},onError:(Object _){if(!closed.isCompleted)closed.complete();},cancelOnError:true);
  socket.add(chunked?utf8.encode('1\r\n{\r\n'):[123]);await socket.flush();
 }
 Future<String?> receipt()=>transport.receipt(owner,ScannerRegistrationKey(actor:fixture.actor,company:fixture.company,device:fixture.device,handle:fixture.handle,publicKeyHex:fixture.publicKey),fixture.nonce,fixture.challengeId);
 Future<void> close() async {await owner.dispose();httpClient.close();for(final socket in sockets){socket.destroy();}await server.close(force:true);await auth.dispose();await directory.delete(recursive:true);if(fixtureFailure!=null)throw fixtureFailure!;}
}
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 test('actual trusted TLS/IOClient response binds exact request and receipt schema',() async {
  final f=_Tls();await f.open((r,b) async {r.response.headers.contentType=ContentType.json;r.response.write(jsonEncode({'schema':1,'requestId':b['requestId'],'operation':b['operation'],'receipt':null}));await r.response.close();});
  try{expect(await f.receipt(),isNull);expect(f.requests,1);}finally{await f.close();}
 });
 test('actual IOClient non200/redirect/oversized unconsumed body aborts owned connection',() async {
  for(final mode in ['error','redirect','oversized']){
   final f=_Tls();await f.open((r,b) async {
    r.response.headers.contentType=ContentType.json;
    if(mode=='error'){r.response.statusCode=503;}else if(mode=='redirect'){r.response.statusCode=307;r.response.headers.set('location','https://foreign-fixture.invalid/credential-leak');}else{r.response.contentLength=20000;}
    await f.stall(r);
   });
   try{await expectLater(f.receipt(),throwsStateError);await f.closed.future.timeout(const Duration(seconds:3));expect(f.requests,1);}finally{await f.close();}
  }
 });
 test('one absolute15s budget aborts slow headers then stalled TLS body (not15s plus15s)',() async {
  final f=_Tls();await f.open((r,b) async {await Future<void>.delayed(const Duration(seconds:14));r.response.headers.contentType=ContentType.json;await f.stall(r);});
  try{
   final clock=Stopwatch()..start();await expectLater(f.receipt(),throwsStateError);await f.closed.future.timeout(const Duration(seconds:3));
   expect(clock.elapsed,lessThan(const Duration(seconds:20)));expect(clock.elapsed,greaterThan(const Duration(seconds:14)));expect(f.requests,1);
  }finally{await f.close();}
 },timeout:const Timeout(Duration(seconds:30)));
 test('late headers after owner retirement cancel their unconsumed response stream',() async {
  final f=_Tls();await f.open((r,b) async {throw StateError('late-header fixture must not use the network');});
  final delayed=_LateHeaders(),cancelled=Completer<void>();
  final body=StreamController<List<int>>(onCancel:(){if(!cancelled.isCompleted)cancelled.complete();});
  final transport=ScannerRegistrationTransport.forTesting(origin:f.transport.origin,client:delayed,enabled:true);
  try{
   final pending=transport.receipt(f.owner,ScannerRegistrationKey(actor:fixture.actor,company:fixture.company,device:fixture.device,handle:fixture.handle,publicKeyHex:fixture.publicKey),fixture.nonce,fixture.challengeId);
   final rejected=expectLater(pending,throwsStateError);await delayed.started.future;await f.owner.dispose();await rejected;
   delayed.response.complete(http.StreamedResponse(body.stream,200,headers:{'content-type':'application/json'}));
   await cancelled.future.timeout(const Duration(seconds:1));expect(f.requests,0);
  }finally{await body.close();await f.close();}
 });
 test('headers acquired immediately before owner post-await invalidation are still disposed',() async {
  final f=_Tls();await f.open((r,b) async {throw StateError('controlled header race must not use the network');});
  final cancelled=Completer<void>(),body=StreamController<List<int>>(onCancel:(){if(!cancelled.isCompleted)cancelled.complete();});
  final controlled=_RetiringHeaders(http.StreamedResponse(body.stream,200,headers:{'content-type':'application/json'}),f.owner.invalidate);
  final transport=ScannerRegistrationTransport.forTesting(origin:f.transport.origin,client:controlled,enabled:true);
  try{
   await expectLater(transport.receipt(f.owner,ScannerRegistrationKey(actor:fixture.actor,company:fixture.company,device:fixture.device,handle:fixture.handle,publicKeyHex:fixture.publicKey),fixture.nonce,fixture.challengeId),throwsStateError);
   await cancelled.future.timeout(const Duration(seconds:1));expect(f.requests,0);
  }finally{await body.close();await f.close();}
 });
 test('actual TLS oversized chunk and invalid UTF8 reject without decoding unbounded data',() async {
  for(final bytes in [List.filled(17000,32),[255]]){
   final f=_Tls();await f.open((r,b) async {r.response.headers.contentType=ContentType.json;r.response.add(bytes);await r.response.close();});
   try{await expectLater(f.receipt(),throwsStateError);expect(f.requests,1);}finally{await f.close();}
  }
 });
}
