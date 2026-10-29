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

class _Tls {
 late Directory directory;late HttpServer server;late IOClient httpClient;late SupabaseClient auth;
 late ScannerRegistrationSession owner;late ScannerRegistrationTransport transport;
 final closed=Completer<void>();int requests=0;Object? fixtureFailure;
 Future<void> open(Future<void> Function(HttpRequest request,Map<String,dynamic> body) handle) async {
  directory=await Directory.systemTemp.createTemp('qr-registration-tls-');
  final cert=File('${directory.path}/cert.pem'),key=File('${directory.path}/key.pem');
  final generated=await Process.run('openssl',['req','-x509','-newkey','rsa:2048','-nodes','-keyout',key.path,'-out',cert.path,'-days','1','-subj','/CN=localhost','-addext','subjectAltName=DNS:localhost,IP:127.0.0.1']);
  if(generated.exitCode!=0)throw StateError('ephemeral TLS fixture unavailable');
  final context=SecurityContext()..useCertificateChain(cert.path)..usePrivateKey(key.path);
  server=await HttpServer.bindSecure(InternetAddress.loopbackIPv4,0,context);
  server.listen((request) async {
   requests++;request.response.done.then((_) {if(!closed.isCompleted)closed.complete();},onError:(Object _) {if(!closed.isCompleted)closed.complete();});
   try{
    expect(request.method,'POST');expect(request.uri.path,'/qr/scanner/registration');expect(request.headers.value('authorization'),'Bearer ${jsonDecode(fixture.sdkSession())['access_token']}');
    final body=jsonDecode(await utf8.decoder.bind(request).join()) as Map<String,dynamic>;
    await handle(request,body);
   }catch(error){if(error is TestFailure)fixtureFailure=error;try{await request.response.close();}catch(_){}}
  });
  final trusted=SecurityContext(withTrustedRoots:false)..setTrustedCertificates(cert.path);
  httpClient=IOClient(HttpClient(context:trusted));
  auth=SupabaseClient('https://qr-auth-fixture.invalid','synthetic-public',authOptions:const AuthClientOptions(autoRefreshToken:false),httpClient:MockClient((r) async {
   expect(r.url.origin,'https://qr-auth-fixture.invalid');expect(r.url.path,'/auth/v1/user');expect(r.url.query,isEmpty);
   return http.Response(jsonEncode((jsonDecode(fixture.sdkSession()) as Map)['user']),200,headers:{'content-type':'application/json'});
  }));await auth.auth.setInitialSession(fixture.sdkSession());owner=ScannerRegistrationSession(auth);
  transport=ScannerRegistrationTransport.forTesting(origin:Uri(scheme:'https',host:'127.0.0.1',port:server.port),client:httpClient,enabled:true);
 }
 Future<String?> receipt()=>transport.receipt(owner,ScannerRegistrationKey(actor:fixture.actor,company:fixture.company,device:fixture.device,handle:fixture.handle,publicKeyHex:fixture.publicKey),fixture.nonce,fixture.challengeId);
 Future<void> close() async {await owner.dispose();httpClient.close();await server.close(force:true);await auth.dispose();await directory.delete(recursive:true);if(fixtureFailure!=null)throw fixtureFailure!;}
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
    r.response.write('{');await r.response.flush();
   });
   try{await expectLater(f.receipt(),throwsStateError);await f.closed.future.timeout(const Duration(seconds:3));expect(f.requests,1);}finally{await f.close();}
  }
 });
 test('one absolute15s budget aborts slow headers then stalled TLS body (not15s plus15s)',() async {
  final f=_Tls();await f.open((r,b) async {await Future<void>.delayed(const Duration(seconds:14));r.response.headers.contentType=ContentType.json;r.response.write('{');await r.response.flush();});
  try{
   final clock=Stopwatch()..start();await expectLater(f.receipt(),throwsStateError);await f.closed.future.timeout(const Duration(seconds:3));
   expect(clock.elapsed,lessThan(const Duration(seconds:20)));expect(clock.elapsed,greaterThan(const Duration(seconds:14)));expect(f.requests,1);
  }finally{await f.close();}
 },timeout:const Timeout(Duration(seconds:30)));
 test('actual TLS oversized chunk and invalid UTF8 reject without decoding unbounded data',() async {
  for(final bytes in [List.filled(17000,32),[255]]){
   final f=_Tls();await f.open((r,b) async {r.response.headers.contentType=ContentType.json;r.response.add(bytes);await r.response.close();});
   try{await expectLater(f.receipt(),throwsStateError);expect(f.requests,1);}finally{await f.close();}
  }
 });
}
