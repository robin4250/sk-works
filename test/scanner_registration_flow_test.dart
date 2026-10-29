import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sk_works/features/qr_attendance/scanner_registration_controller.dart';
import 'package:sk_works/features/qr_attendance/scanner_registration_key.dart';
import 'package:sk_works/features/qr_attendance/scanner_registration_page.dart';
import 'package:sk_works/features/qr_attendance/scanner_registration_pending.dart';
import 'package:sk_works/features/qr_attendance/scanner_registration_transport.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const actor='00000000-0000-4000-8000-000000000001',company='00000000-0000-4000-8000-000000000002',device='00000000-0000-4000-8000-000000000003',sid='00000000-0000-4000-8000-000000000004',challengeId='00000000-0000-4000-8000-000000000005',nonce='00000000-0000-4000-8000-000000000006';
final publicKey='302a300506032b6570032100${'ab'*32}',handle=sha256.convert(utf8.encode('sko.qr.scanner.custody.v1\n$actor\n$company\n$device')).toString();
final signature=base64Url.encode(List.filled(64,1)).replaceAll('=',''),rawProof='cd'*32;
String sdkSession({String actorId=actor,String sessionId=sid}) {
 String part(Object value)=>base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=','');
 return jsonEncode({'access_token':'${part({'alg':'HS256'})}.${part({'sub':actorId,'session_id':sessionId,'exp':4102444800,'is_anonymous':false})}.${base64Url.encode(List.filled(32,7)).replaceAll('=','')}',
 'refresh_token':'synthetic','expires_in':3600,'token_type':'bearer','user':{'id':actorId,'is_anonymous':false,'aud':'authenticated','created_at':'2026-01-01T00:00:00Z','app_metadata':{},'user_metadata':{}}});
}
Map<String,dynamic> copy(Map<String,dynamic> value)=>Map<String,dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
class _Wire extends http.BaseClient {
 _Wire(this.dispatch);final Future<Map<String,dynamic>> Function(Map<String,dynamic>) dispatch;
 @override Future<http.StreamedResponse> send(http.BaseRequest request) async {
  expect(request.url,Uri.parse('https://qr-runtime-fixture.invalid/qr/scanner/registration'));expect(request.method,'POST');expect(request.followRedirects,isFalse);expect(request,isA<http.AbortableRequest>());
  expect(request.headers.entries.where((e)=>e.key.toLowerCase()=='authorization').single.value,'Bearer ${jsonDecode(sdkSession())['access_token']}');
  final body=jsonDecode(await request.finalize().bytesToString()) as Map<String,dynamic>;
  final result=await dispatch(body);return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(result))),200,headers:{'content-type':'application/json; charset=utf-8'});
 }
}
// Delegate all observed session behavior to the pinned, real SDK instance.
// Only subscription/lookup requests are counted; no synthetic Auth stream.
class _ObservedAuth extends Fake implements GoTrueClient {
 _ObservedAuth(this.actual);
 final GoTrueClient actual;
 int subscriptions=0,lookups=0;
 @override Session? get currentSession=>actual.currentSession;
 @override Stream<AuthState> get onAuthStateChange {subscriptions++;return actual.onAuthStateChange;}
 @override Future<UserResponse> getUser([String? jwt]) {lookups++;return actual.getUser(jwt);}
}
class _ObservedClient extends Fake implements SupabaseClient {
 _ObservedClient(SupabaseClient actual):observed=_ObservedAuth(actual.auth);
 final _ObservedAuth observed;
 @override GoTrueClient get auth=>observed;
}
class _Fixture {
 static const keyChannel=MethodChannel('com.skworks.sko/qr_scanner_key'),journalChannel=MethodChannel('com.skworks.sko/qr_scanner_pending');
 late SupabaseClient client;late ScannerRegistrationController controller;late _Wire wire;
 Map<String,dynamic>? stored,serverChallenge;bool keyExists=false,proofAccepted=false,registered=false;
 bool loseChallenge=false,loseProof=false,loseComplete=false;
 String? loseJournalAck,corruptJournalAck;
 final order=<String>[],operations=<String>[];
 Future<void> open({bool enabled=true}) async {
  client=SupabaseClient('https://qr-auth-fixture.invalid','synthetic-public',authOptions:const AuthClientOptions(autoRefreshToken:false),httpClient:MockClient((r) async {
   expect(r.method,'GET');expect(r.url.origin,'https://qr-auth-fixture.invalid');expect(r.url.path,'/auth/v1/user');expect(r.url.query,isEmpty);
   final token=r.headers.entries.where((e)=>e.key.toLowerCase()=='authorization').single.value.substring(7);
   final claims=jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[1])))) as Map;
   return http.Response(jsonEncode({'id':claims['sub'],'is_anonymous':false,'aud':'authenticated','created_at':'2026-01-01T00:00:00Z','app_metadata':{},'user_metadata':{}}),200,headers:{'content-type':'application/json'});
  }));await client.auth.setInitialSession(sdkSession());
  wire=_Wire(dispatch);controller=makeController(enabled:enabled);
  final messenger=TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(keyChannel,(call) async {
   if(call.method=='cancel')return null;final a=call.arguments as Map;expect(a['actor'],actor);expect(a['company'],company);expect(a['device'],device);
   if(call.method=='prepare'){keyExists=true;return {'handle':handle,'publicKeyHex':publicKey};}
   expect(call.method,'sign');expect(a['session'],sid);expect(a['challenge'],serverChallenge);expect(a['handle'],handle);return {'handle':handle,'signature':signature};
  });
  messenger.setMockMethodCallHandler(journalChannel,(call) async {
   if(call.method=='cancel')return null;final a=call.arguments as Map;
   if(a['actor']!=actor || a['company']!=company || a['session']!=sid)throw PlatformException(code:'unavailable');
   if(call.method=='read')return stored==null?{'status':'absent'}:{'status':'found','pending':copy(stored!)};
   if(call.method=='createNewLogicalDeviceIntent'){
    if(stored!=null || keyExists)throw PlatformException(code:'unavailable');
    stored={'schema':1,'actor':actor,'company':company,'session':sid,'device':device,'handle':handle,'nonce':nonce,'version':0,'stage':'key_pending','publicKeyHex':null,'challenge':null,'challengeRequestId':null,'proofRequestIds':<String>[],'completionRequestId':null,'registrationEventId':null};order.add('journal:key_pending:ack');return copy(stored!);
   }
   expect(call.method,'advance');expect(a['expectedVersion'],stored!['version']);
   final next=a['nextStage'] as String,patch=Map<String,dynamic>.from(a['patch'] as Map);
   final updated=copy(stored!)..['stage']=next..['version']=(stored!['version'] as int)+1;
   for(final entry in patch.entries){if(entry.key=='proofRequestId'){updated['proofRequestIds']=[...(stored!['proofRequestIds'] as List),entry.value];}else{updated[entry.key]=entry.value;}}
   stored=updated;order.add('journal:$next:ack');
   if(loseJournalAck==next){loseJournalAck=null;throw PlatformException(code:'synthetic_ack_lost');}
   final result=copy(stored!);if(corruptJournalAck==next){corruptJournalAck=null;result['nonce']=actor;}return result;
  });
 }
 ScannerRegistrationController makeController({bool enabled=true,SupabaseClient? ownerClient})=>ScannerRegistrationController(client:ownerClient??client,company:company,enabled:enabled,keys:ScannerRegistrationKeyCustody(client,enabled:enabled,channel:keyChannel),journal:ScannerRegistrationJournal(enabled:enabled,channel:journalChannel),transport:ScannerRegistrationTransport.forTesting(origin:Uri.parse('https://qr-runtime-fixture.invalid'),client:wire,enabled:enabled));
 Future<Map<String,dynamic>> dispatch(Map<String,dynamic> b) async {
  final op=b['operation'] as String;operations.add(op);order.add('http:$op');
  final base=<String,dynamic>{'schema':1,'requestId':b['requestId'],'operation':op};
  switch(op){
   case 'challenge':
    expect(stored!['stage'],'challenge_sent');expect(b['requestId'],stored!['challengeRequestId']);
    final now=DateTime.now().millisecondsSinceEpoch;
    serverChallenge={'id':challengeId,'company':company,'actor':actor,'session':sid,'device':device,'keyHex':publicKey,'nonce':nonce,'createdMs':now-1000,'expiresMs':now+88000,'databaseNowMs':now};
    if(loseChallenge){loseChallenge=false;throw http.ClientException('synthetic lost challenge acknowledgement');}return {...base,'challenge':serverChallenge};
   case 'challenge_result':return {...base,'challenge':serverChallenge};
   case 'proof':
    expect(stored!['stage'],'proof_sent');expect(b['requestId'],(stored!['proofRequestIds'] as List).last);expect(b['challengeId'],challengeId);
    if(b['password']!='synthetic-secondary-password')return {...base,'accepted':false};proofAccepted=true;
    if(loseProof){loseProof=false;throw http.ClientException('synthetic lost proof acknowledgement');}
    return {...base,'accepted':true,'proof':rawProof,'expiresAt':DateTime.now().toUtc().add(const Duration(seconds:60)).toIso8601String()};
   case 'proof_result':return {...base,'issuance':{'status':proofAccepted?'committed_unrecoverable':'not_found'}};
   case 'complete':
    expect(stored!['stage'],'completion_sent');expect(b['requestId'],stored!['completionRequestId']);expect(b['challengeId'],challengeId);expect(b['proof'],rawProof);expect(b['signature'],signature);expect(proofAccepted,isTrue);registered=true;
    if(loseComplete){loseComplete=false;throw http.ClientException('synthetic lost completion acknowledgement');}return {...base,'deviceId':device};
   case 'result':return {...base,'receipt':registered?{'challengeId':challengeId,'deviceId':device,'registrationEventId':'1'}:null};
   default:throw StateError('unexpected fixture operation');
  }
 }
 Future<void> passwordStage() async {await controller.load();await controller.createExplicitNewLogicalDevice();await controller.prepareKey();await controller.startChallenge();expect(controller.view,ScannerRegistrationView.password);}
 Future<void> close() async {controller.dispose();await client.dispose();TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(keyChannel,null);TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(journalChannel,null);}
 void noSecrets(){final s=jsonEncode(stored);for(final secret in ['synthetic-secondary-password',rawProof,signature,jsonDecode(sdkSession())['access_token'] as String]){expect(s, isNot(contains(secret)));}}
}
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 late _Fixture f;setUp(() async {f=_Fixture();await f.open();});tearDown(() async {await f.close();});
 test('load retired by immediate disposal never reacquires SDK session resources',() async {
  f.controller.dispose();final observed=_ObservedClient(f.client);
  f.controller=f.makeController(ownerClient:observed);
  final loading=f.controller.load();f.controller.dispose();await loading;
  expect(observed.observed.subscriptions,0,reason:'retired load must not subscribe to Auth');
  expect(observed.observed.lookups,0);expect(f.stored,isNull);expect(f.operations,isEmpty);
 });
 test('concurrent initial loads acquire only the latest SDK session owner',() async {
  f.controller.dispose();final observed=_ObservedClient(f.client);
  f.controller=f.makeController(ownerClient:observed);
  final first=f.controller.load(),second=f.controller.load();await Future.wait([first,second]);
  expect(observed.observed.subscriptions,1,reason:'superseded load must not subscribe to Auth');
  expect(f.controller.view,ScannerRegistrationView.newLogicalDevice);
  expect(f.stored,isNull);expect(f.operations,isEmpty);
 });
 test('actual controller/native-bridge/HTTP contract orders durable ACK before each write',() async {
  await f.passwordStage();await f.controller.submitPassword('synthetic-secondary-password');expect(f.controller.view,ScannerRegistrationView.confirmed);
  for(final pair in [['challenge_sent','challenge'],['proof_sent','proof'],['completion_sent','complete']]){expect(f.order.indexOf('journal:${pair[0]}:ack'),lessThan(f.order.indexOf('http:${pair[1]}')));}
  expect(f.operations.where((v)=>v=='complete'),hasLength(1));expect(f.stored!['registrationEventId'],'1');f.noSecrets();
 });
 test('lost challenge acknowledgement reconciles original scope without another issuance',() async {
  await f.controller.load();await f.controller.createExplicitNewLogicalDevice();await f.controller.prepareKey();f.loseChallenge=true;await f.controller.startChallenge();expect(f.controller.view,ScannerRegistrationView.uncertain);
  await f.controller.reconcile();expect(f.controller.view,ScannerRegistrationView.password);expect(f.operations.where((v)=>v=='challenge'),hasLength(1));expect(f.stored!['challenge']['id'],challengeId);
 });
 test('lost raw proof is historical evidence only; reload never reissues or completes',() async {
  await f.passwordStage();f.loseProof=true;await f.controller.submitPassword('synthetic-secondary-password');expect(f.stored!['stage'],'proof_sent');
  await f.controller.reconcile();expect(f.controller.view,ScannerRegistrationView.proofLost);f.controller.dispose();f.controller=f.makeController();await f.controller.load();expect(f.controller.view,ScannerRegistrationView.proofLost);
  expect(f.operations.where((v)=>v=='proof'),hasLength(1));expect(f.operations, isNot(contains('complete')));f.noSecrets();
 });
 test('lost completion acknowledgement reads one original receipt and never resends',() async {
  await f.passwordStage();f.loseComplete=true;await f.controller.submitPassword('synthetic-secondary-password');expect(f.stored!['stage'],'completion_sent');await f.controller.reconcile();expect(f.controller.view,ScannerRegistrationView.confirmed);
  await f.controller.reconcile();expect(f.operations.where((v)=>v=='complete'),hasLength(1));expect(f.operations.where((v)=>v=='proof'),hasLength(1));f.noSecrets();
 });
 test('unacknowledged/corrupt durable stage prevents HTTP write and unknown missing result prevents retry',() async {
  for(final corrupt in [false,true]){
   if(f.stored!=null){await f.close();f=_Fixture();await f.open();}
   await f.controller.load();await f.controller.createExplicitNewLogicalDevice();await f.controller.prepareKey();
   if(corrupt){f.corruptJournalAck='challenge_sent';}else{f.loseJournalAck='challenge_sent';}
   await f.controller.startChallenge();expect(f.operations,isEmpty);await f.controller.reconcile();expect(f.operations.where((v)=>v=='challenge'),isEmpty);expect(f.controller.view,ScannerRegistrationView.uncertain);
  }
 });
 test('known rejected password permits one explicit new attempt; unknown proof not_found does not',() async {
  await f.passwordStage();await f.controller.submitPassword('synthetic-wrong');expect(f.controller.view,ScannerRegistrationView.wrongPassword);expect(f.stored!['proofRequestIds'],hasLength(1));
  await f.controller.submitPassword('synthetic-secondary-password');expect(f.controller.view,ScannerRegistrationView.confirmed);expect(f.stored!['proofRequestIds'],hasLength(2));f.noSecrets();
 });
 test('same-UID different SID cannot adopt journal or make another server write',() async {
  await f.passwordStage();final before=List<String>.from(f.operations),snapshot=jsonEncode(f.stored);
  await f.client.auth.setInitialSession(sdkSession(sessionId:nonce));await Future<void>.delayed(Duration.zero);await f.controller.submitPassword('synthetic-secondary-password');expect(f.operations,before);
  f.controller.dispose();f.controller=f.makeController();await f.controller.load();expect(f.controller.view,ScannerRegistrationView.blocked);expect(jsonEncode(f.stored),snapshot);
 });
 test('missing existing recovery state never automatically initializes or rotates identity',() async {
  await f.passwordStage();final operations=List<String>.from(f.operations);f.stored=null;await f.controller.reconcile();expect(f.controller.view,ScannerRegistrationView.blocked);expect(f.stored,isNull);expect(f.operations,operations);
  await f.controller.load();expect(f.controller.view,ScannerRegistrationView.blocked);expect(f.stored,isNull);
 });
 testWidgets('unexposed page requires explicit new setup and clears password through real controller flow',(tester) async {
  await tester.pumpWidget(MaterialApp(home:ScannerRegistrationPage(controller:f.controller,companyName:'テスト会社')));await tester.pumpAndSettle();
  expect(f.stored,isNull);expect(f.operations,isEmpty);
  final begin=find.byKey(const Key('scanner-new-logical-device'));expect(tester.widget<FilledButton>(begin).onPressed,isNull);
  await tester.tap(find.byType(CheckboxListTile));await tester.pump();await tester.tap(begin);await tester.pumpAndSettle();
  expect(f.stored!['stage'],'key_pending');expect(f.operations,isEmpty);
  Future<void> invokeAndDrain(Finder button) async {
   await tester.runAsync(() async {
    await tester.tap(button);
    final clock=Stopwatch()..start();
    while(f.controller.busy){if(clock.elapsed>const Duration(seconds:5))throw StateError('fixture runtime did not finish');await Future<void>.delayed(const Duration(milliseconds:1));}
   });
   await tester.pumpAndSettle();
  }
  await invokeAndDrain(find.widgetWithText(FilledButton,'この端末の鍵を準備'));
  await invokeAndDrain(find.widgetWithText(FilledButton,'登録手続きを開始'));
  await tester.enterText(find.byKey(const Key('scanner-dedicated-password')),'synthetic-secondary-password');
  await invokeAndDrain(find.widgetWithText(FilledButton,'本人確認して登録'));
  expect(f.controller.view,ScannerRegistrationView.confirmed);expect(find.text('synthetic-secondary-password'),findsNothing);expect(find.byType(TextField),findsNothing);f.noSecrets();
  await tester.pumpWidget(const SizedBox());
 });
 testWidgets('lost proof page offers read-only reconciliation and no password/reissue action',(tester) async {
  await tester.runAsync(() async {await f.passwordStage();f.loseProof=true;await f.controller.submitPassword('synthetic-secondary-password');await f.controller.reconcile();});
  await tester.pumpWidget(MaterialApp(home:ScannerRegistrationPage(controller:f.controller,companyName:'テスト会社')));await tester.pumpAndSettle();
  expect(f.controller.view,ScannerRegistrationView.proofLost);expect(find.byType(TextField),findsNothing);expect(find.widgetWithText(FilledButton,'本人確認して登録'),findsNothing);expect(f.operations.where((v)=>v=='proof'),hasLength(1));
  await tester.tap(find.byKey(const Key('scanner-reconcile')));await tester.pumpAndSettle();expect(f.operations.where((v)=>v=='proof'),hasLength(1));expect(f.operations,isNot(contains('complete')));
  await tester.pumpWidget(const SizedBox());
 });
 testWidgets('OFF page exposes no registration action or password field',(tester) async {
  f.controller.dispose();f.controller=f.makeController(enabled:false);await tester.pumpWidget(MaterialApp(home:ScannerRegistrationPage(controller:f.controller,companyName:'テスト会社')));await tester.pump();
  expect(find.text('スキャナー登録は準備中です。'),findsOneWidget);expect(find.byType(TextField),findsNothing);expect(f.operations,isEmpty);expect(f.stored,isNull);
  await tester.pumpWidget(const SizedBox());
 });
}
