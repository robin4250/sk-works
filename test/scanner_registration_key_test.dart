import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sk_works/features/qr_attendance/scanner_registration_key.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const actor = '00000000-0000-4000-8000-000000000001';
const company = '00000000-0000-4000-8000-000000000002';
const device = '00000000-0000-4000-8000-000000000003';
const sid = '00000000-0000-4000-8000-000000000004';
const other = '00000000-0000-4000-8000-000000000005';
final publicKey = '302a300506032b6570032100${'ab' * 32}';
final handle = sha256.convert(utf8.encode('sko.qr.scanner.custody.v1\n$actor\n$company\n$device')).toString();
Map<String,dynamic> user(String id) => {'id': id, 'aud':'authenticated','created_at':'2026-01-01T00:00:00Z','app_metadata':{},'user_metadata':{},'is_anonymous':false};
String session(String id, {String sessionId = sid}) {
 String part(Object v) => base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
 return jsonEncode({'access_token':'${part({'alg':'HS256'})}.${part({'sub':id,'session_id':sessionId,'role':'authenticated','is_anonymous':false,'exp':4102444800})}.${base64Url.encode(List.filled(32, 7)).replaceAll('=', '')}',
 'refresh_token':'synthetic', 'token_type':'bearer','expires_in':3600,'user':user(id)});
}
Map<String,dynamic> challenge() => {'id':actor,'company':company,'actor':actor,'session':sid,'device':device,'nonce':sid,'keyHex':publicKey,'createdMs':1000,'expiresMs':2000,'databaseNowMs':1500};
void main() {
 TestWidgetsFlutterBinding.ensureInitialized();
 const channel = MethodChannel('com.skworks.sko/qr_scanner_key');
 late SupabaseClient client;
 late StreamController<AuthState> changes;
 final nativeCalls = <MethodCall>[], requests = <http.Request>[];
 Future<Object?> Function(MethodCall)? native;
 Future<void> Function()? beforeAuth;
 String authActor = actor;
 setUp(() async {
  changes = StreamController<AuthState>.broadcast(); nativeCalls.clear(); requests.clear(); beforeAuth = null; authActor = actor;
  client = SupabaseClient('https://qr-key-fixture.invalid','synthetic-public',authOptions: const AuthClientOptions(autoRefreshToken:false),httpClient:MockClient((r) async {
   requests.add(r);
   if(r.method=='POST' && r.url.path=='/auth/v1/token')return http.Response(session(actor),200,headers:{'content-type':'application/json'});
   expect(r.method,'GET');expect(r.url.toString(),'https://qr-key-fixture.invalid/auth/v1/user');
   expect(r.headers['Authorization'],'Bearer ${jsonDecode(session(actor))['access_token']}');
   await beforeAuth?.call();return http.Response(jsonEncode(user(authActor)),200,headers:{'content-type':'application/json'});
  }));
  await client.auth.setInitialSession(session(actor));
  native = (call) async => call.method == 'prepare' ? {'handle':handle,'publicKeyHex':publicKey} : {'handle':handle,'signature':base64Url.encode(List.filled(64, 1)).replaceAll('=', '')};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,(call) async {
   nativeCalls.add(call);if(call.method=='cancel')return null;return native!(call);
  });
 });
 tearDown(() async {
  await changes.close();await client.dispose();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,null);
 });
 ScannerRegistrationKeyCustody custody({bool enabled=true, bool actualStream=false}) => ScannerRegistrationKeyCustody(client,enabled:enabled,channel:channel,authChanges:actualStream?null:changes.stream);
 test('default OFF does not call Auth or native key storage',() async {
  final c=ScannerRegistrationKeyCustody(client,channel:channel);await expectLater(c.prepare(company:company,device:device),throwsStateError);
  expect(requests,isEmpty);expect(nativeCalls,isEmpty);c.dispose();
 });
 test('actual SDK initial replay plus exact Auth lookup returns only scope-bound public metadata',() async {
  final c=custody(actualStream:true);final key=await c.prepare(company:company,device:device);
  expect(key.handle,handle);expect(key.actor,actor);expect(key.publicKeyHex,publicKey);
  expect(nativeCalls.single.method,'prepare');final args=nativeCalls.single.arguments as Map;
  expect(args.keys.toSet(),{'requestId','actor','company','device'});expect(args['actor'],actor);expect(args['company'],company);expect(args['device'],device);
  expect(jsonEncode(args),isNot(contains('access_token')));expect(requests,hasLength(1));c.dispose();
 });
 test('actual SDK cached signedIn after password login allows prepare; fresh same-SID login invalidates',() async {
  await client.auth.signInWithPassword(email:'synthetic-qr@example.invalid',password:'synthetic-password');
  final c=custody(actualStream:true);final key=await c.prepare(company:company,device:device);expect(key.actor,actor);c.dispose();
  final next=custody(actualStream:true);final before=nativeCalls.length;
  beforeAuth=() async {await client.auth.signInWithPassword(email:'synthetic-qr@example.invalid',password:'synthetic-password');await Future<void>.delayed(Duration.zero);};
  await expectLater(next.prepare(company:company,device:device),throwsStateError);expect(nativeCalls.length,before);next.dispose();
 });
 test('expired SDK session refuses before Auth lookup or native operation',() async {
  final expired=jsonDecode(session(actor)) as Map<String,dynamic>;expired['expires_at']=1;expired['expires_in']=0;
  final parts=(expired['access_token'] as String).split('.'),claims=jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize((expired['access_token'] as String).split('.')[1])))) as Map<String,dynamic>;
  claims['exp']=1;parts[1]=base64Url.encode(utf8.encode(jsonEncode(claims))).replaceAll('=', '');expired['access_token']=parts.join('.');
  await client.auth.setInitialSession(jsonEncode(expired));expect(client.auth.currentSession!.isExpired,isTrue);
  final c=custody();await expectLater(c.prepare(company:company,device:device),throwsStateError);
  expect(requests,isEmpty);expect(nativeCalls,isEmpty);c.dispose();
 });
 test('already background custody refuses before Auth and native calls',() async {
  final c=custody();c.didChangeAppLifecycleState(AppLifecycleState.paused);
  await expectLater(c.prepare(company:company,device:device),throwsStateError);expect(requests,isEmpty);expect(nativeCalls,isEmpty);c.dispose();
 });
 test('prepared key signs only original challenge and never passes a password or private key',() async {
  final c=custody();final key=await c.prepare(company:company,device:device);final signature=await c.signRegistration(key:key,challenge:challenge());
  expect(signature.length,86);final args=nativeCalls.last.arguments as Map;
  expect(args.keys.toSet(),{'requestId','actor','company','device','session','handle','challenge'});expect(args['challenge'],challenge());
  final count=nativeCalls.length;await expectLater(c.signRegistration(key:key,challenge:{...challenge(),'actor':other}),throwsStateError);expect(nativeCalls.length,count);c.dispose();
 });
 test('foreign Auth user and corrupt native public metadata fail closed',() async {
  final c=custody();authActor=other;await expectLater(c.prepare(company:company,device:device),throwsStateError);expect(nativeCalls,isEmpty);
  authActor=actor;native=(_) async=>{'handle':'0'*64,'publicKeyHex':publicKey};await expectLater(c.prepare(company:company,device:device),throwsStateError);c.dispose();
 });
 test('queued A to B to A history during Auth lookup prevents native operation',() async {
  final c=custody();beforeAuth=() async {changes.add(AuthState(AuthChangeEvent.signedIn,Session.fromJson(jsonDecode(session(other)))!));changes.add(AuthState(AuthChangeEvent.signedIn,client.auth.currentSession));await Future<void>.delayed(Duration.zero);};
  await expectLater(c.prepare(company:company,device:device),throwsStateError);expect(nativeCalls,isEmpty);c.dispose();
 });
 test('dispose/background cancel a hanging exact Auth lookup promptly without native work',() async {
  for(final mode in ['dispose','background']){
   final c=custody(),entered=Completer<void>(),gate=Completer<void>();
   beforeAuth=() {entered.complete();return gate.future;};
   final pending=c.prepare(company:company,device:device),rejected=expectLater(pending,throwsStateError);await entered.future;
   if(mode=='dispose'){c.dispose();}else{c.didChangeAppLifecycleState(AppLifecycleState.paused);}
   await rejected.timeout(const Duration(seconds:1));expect(nativeCalls,isEmpty);
   gate.complete();await Future<void>.delayed(Duration.zero);c.dispose();
  }
 });
 test('Auth stream error/completion prevents key operations without unhandled zone errors',() async {
  for(final close in [false,true]){
   if(changes.isClosed)changes=StreamController<AuthState>.broadcast();final c=custody();
   beforeAuth=() async {if(close){await changes.close();}else{changes.addError(StateError('synthetic secret'));await Future<void>.delayed(Duration.zero);}};
   await expectLater(c.prepare(company:company,device:device),throwsStateError);expect(nativeCalls,isEmpty);c.dispose();
  }
 });
 test('dispose, lifecycle and session switch cancel pending native work and reject late results',() async {
  for(final mode in ['dispose','background','session']){
   final c=custody(),gate=Completer<Object?>(),entered=Completer<void>();
   native=(_) {entered.complete();return gate.future;};final pending=c.prepare(company:company,device:device);final rejected=expectLater(pending,throwsStateError);await entered.future;
   if(mode=='dispose'){c.dispose();}else if(mode=='background'){c.didChangeAppLifecycleState(AppLifecycleState.paused);}else{await client.auth.setInitialSession(session(other));changes.add(AuthState(AuthChangeEvent.signedIn,client.auth.currentSession));await Future<void>.delayed(Duration.zero);}
   gate.complete({'handle':handle,'publicKeyHex':publicKey});await rejected;expect(nativeCalls.last.method,'cancel');c.dispose();
   await client.auth.setInitialSession(session(actor));
  }
 });
}
