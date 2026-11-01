import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/auth/apple_successor_client_preparation.dart';
import 'package:sk_works/features/auth/apple_successor_https_delivery.dart';

const actor = '40000000-0000-0000-0000-000000000001';
const other = '40000000-0000-0000-0000-000000000002';
const requestId = '40000000-0000-0000-0000-000000000003';
const originalSid = '40000000-0000-0000-0000-000000000004';
const successorSid = '40000000-0000-0000-0000-000000000005';
const project = 'https://owned-sdk-fixture.invalid';
String token(String sid, {String uid = actor}) {
  String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg':'HS256'})}.${part({'sub':uid,'session_id':sid,'exp':4102444800,
    'iat':1767225600,'iss':'$project/auth/v1','aud':'authenticated'})}.${base64Url.encode(List<int>.filled(32,7)).replaceAll('=', '')}';
}
Map<String, dynamic> user({bool apple = false, String uid = actor, String appleSubject = 'owned-apple', String? googleSubject}) => {
  'id':uid,'aud':'authenticated','created_at':'2026-01-01T00:00:00Z',
  'app_metadata':<String,dynamic>{},'user_metadata':<String,dynamic>{},'identities':[
    {'id':googleSubject??'google-$uid','identity_id':uid,'user_id':uid,'provider':'google',
      'identity_data':{'sub':googleSubject??'google-$uid'},'created_at':'2026-01-01T00:00:00Z','updated_at':'2026-01-01T00:00:00Z'},
    if(apple) {'id':appleSubject,'identity_id':requestId,'user_id':uid,'provider':'apple',
      'identity_data':{'sub':appleSubject},'created_at':'2026-01-01T00:00:00Z','updated_at':'2026-01-01T00:00:00Z'},
  ],
};
Map<String,dynamic> initialSession({String uid = actor}) => {'access_token':token(originalSid,uid:uid),
  'refresh_token':'synthetic-original-refresh','token_type':'bearer','expires_in':3600,'user':user(uid:uid)};
Map<String,dynamic> envelope() => {'schema':1,'request_id':requestId,'user_id':actor,
  'session_id':successorSid,'token_type':'bearer','access_token':token(successorSid),'refresh_token':'synthetic-successor-refresh'};
Map<String,dynamic> ack() => {'schema':1,'request_id':requestId,'status':'successor_possession_recorded',
  'retry_allowed':false,'application_adoption_confirmed':false};
class FixtureDelivery extends AppleSuccessorHttpsDelivery {
  FixtureDelivery():super(endpoint:Uri.https('owned-delivery-fixture.invalid','/enroll'),enabled:true);
  int calls = 0;
  String? sentBearer;
  Map<String,dynamic> Function() payload = envelope;
  @override
  Future<Map<String,dynamic>> receiveOnce({required String bearer,required String requestId,
    required String actor,required String password,required String idToken,required String rawNonce}) async {
    calls++; sentBearer=bearer; return payload();
  }
}
class NativeTlsFixture extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<AppleOwnedSessionCoordinator> coordinators;
  late StreamController<AuthState> extra;
  late List<String> requests, ackBearers;
  late int applicationClients, isolatedClients, adoptedUserRequests;
  Future<void> Function(int call)? beforeAdoptedUser;
  late Future<Map<String,dynamic>> Function(String,String) acknowledge;
  String applicationAppleSubject = 'owned-apple';
  String? applicationGoogleSubject;
  String applicationCompany = requestId;
  setUp(() {
    debugDefaultTargetPlatformOverride=TargetPlatform.iOS;
    coordinators=[]; extra=StreamController<AuthState>.broadcast(); requests=[];ackBearers=[];
    applicationClients=isolatedClients=adoptedUserRequests=0;beforeAdoptedUser=null;
    applicationAppleSubject='owned-apple';
    applicationGoogleSubject=null;applicationCompany=requestId;
    acknowledge=(request,bearer) async {expect(request,requestId);ackBearers.add(bearer);return ack();};
  });
  tearDown(() async {
    for(final value in coordinators){await value.dispose();}
    await extra.close();debugDefaultTargetPlatformOverride=null;
  });
  http.Client network({required bool isolated}) {
    if(isolated){isolatedClients++;}else{applicationClients++;}
    return MockClient((request) async {
      final auth=request.headers['Authorization'];
      final successor=auth=='Bearer ${token(successorSid)}';
      requests.add('${isolated?'isolated':'owned'}:${request.method}:${request.url.path}:${successor?'successor':'original'}');
      Object result;
      if(request.url.path.endsWith('/token')){
        expect(request.method,'POST');expect(request.url.queryParameters['grant_type'],'password');
        final sent=jsonDecode(request.body);
        expect(sent['gotrue_meta_security'],{'captcha_token':'synthetic-challenge'});
        expect(sent['email'],'owner@fixture.invalid');expect(sent['password'],'synthetic-password');
        result=initialSession();
      }else if(request.url.path.endsWith('/user')){
        expect(request.method,'GET');
        if(successor&&!isolated){adoptedUserRequests++;await beforeAdoptedUser?.call(adoptedUserRequests);}
        result=user(apple:successor,appleSubject:isolated?'owned-apple':applicationAppleSubject,
          googleSubject:isolated?null:applicationGoogleSubject);
      }else if(request.url.path.endsWith('/company_members')){
        expect(request.method,'GET');result=[{'company_id':isolated?requestId:applicationCompany,'role':'owner'}];
      }else if(request.url.path.endsWith('/logout')){
        expect(request.method,'POST');expect(request.url.queryParameters['scope'],'local');result=<String,dynamic>{};
      }else{throw StateError('unexpected fixture route');}
      return http.Response(jsonEncode(result),200,headers:{'content-type':'application/json'},request:request);
    });
  }
  AppleOwnedSessionCoordinator make({bool enabled = true,Duration operationTimeout=const Duration(seconds:3),
    Duration ackTimeout=const Duration(seconds:1)}) {
    final value=AppleOwnedSessionCoordinator(projectUrl:project,publicKey:'synthetic-public',enabled:enabled,
      operationTimeout:operationTimeout,ackTimeout:ackTimeout,additionalAuthHistory:extra.stream,
      applicationHttpFactory:()=>network(isolated:false),isolatedHttpFactory:()=>network(isolated:true),
      acknowledgePossession:(request,bearer)=>acknowledge(request,bearer));
    coordinators.add(value);return value;
  }
  Future<void> login(AppleOwnedSessionCoordinator value)=>value.signInWithPassword(email:'owner@fixture.invalid',password:'synthetic-password',captchaToken:'synthetic-challenge');
  Future<void> enroll(AppleOwnedSessionCoordinator value,AppleSuccessorHttpsDelivery delivery)=>value.enrollAndAdopt(
    requestId:requestId,delivery:delivery,password:'synthetic-password',idToken:'synthetic-apple-token',rawNonce:'N'*43);

  test('default OFF makes no client/network/ACK and exposes no candidate actor',() async {
    final value=make(enabled:false),delivery=FixtureDelivery();
    await expectLater(login(value),throwsStateError);await expectLater(enroll(value,delivery),throwsStateError);
    expect(value.actorId,isNull);expect(applicationClients,0);expect(isolatedClients,0);expect(delivery.calls,0);expect(ackBearers,isEmpty);
  });
  test('actual SDK password session -> existing isolated preparation -> SDK adoption -> exact successor possession ACK',() async {
    final value=make(),delivery=FixtureDelivery();await login(value);
    expect(value.actorId,actor);expect(value.ownedSessionAdopted,isFalse);
    await enroll(value,delivery);
    expect(value.phase,AppleOwnedSessionPhase.adopted);expect(value.actorId,actor);
    expect(value.ownedSessionAdopted,isTrue);expect(value.possessionAcknowledged,isTrue);
    expect(delivery.sentBearer,token(originalSid));expect(delivery.calls,1);
    expect(ackBearers,[token(successorSid)]);expect(applicationClients,1);expect(isolatedClients,1);
    expect(requests.where((r)=>r.contains('/token:')),hasLength(1),reason:'no refresh exchange or second password session');
    expect(requests.any((r)=>r.contains('/logout:')),isFalse,reason:'no stale-session rollback/logout during adoption');
    await expectLater(enroll(value,delivery),throwsStateError);expect(delivery.calls,1);
  });
  test('real original HTTPS delivery composes all the way through owned SDK adoption and successor ACK',() async {
    final directory=await Directory.systemTemp.createTemp('apple-owned-tls-');
    addTearDown(()=>directory.delete(recursive:true));
    final certificate=await Process.run('openssl',['req','-x509','-newkey','rsa:2048','-nodes','-days','1',
      '-subj','/CN=localhost','-addext','subjectAltName=DNS:localhost,IP:127.0.0.1',
      '-addext','extendedKeyUsage=serverAuth',
      '-keyout','${directory.path}/key.pem','-out','${directory.path}/cert.pem']);
    expect(certificate.exitCode,0);
    final serverContext=SecurityContext()..useCertificateChain('${directory.path}/cert.pem')..usePrivateKey('${directory.path}/key.pem');
    final trusted=SecurityContext(withTrustedRoots:false)..setTrustedCertificates('${directory.path}/cert.pem');
    final server=await HttpServer.bindSecure(InternetAddress.loopbackIPv4,0,serverContext);
    addTearDown(()=>server.close(force:true));
    var calls=0;
    server.listen((request) async {
      calls++;expect(request.method,'POST');expect(request.headers.value('authorization'),'Bearer ${token(originalSid)}');
      expect(request.headers.value('x-sko-request-id'),requestId);
      await request.drain<void>();request.response.headers.contentType=ContentType.json;
      request.response.headers.set('cache-control','no-store');request.response.write(jsonEncode(envelope()));
      await request.response.close();
    });
    final delivery=AppleSuccessorHttpsDelivery(endpoint:Uri.parse('https://127.0.0.1:${server.port}/enroll'),enabled:true,
      clientFactory:()=>NativeTlsFixture().createHttpClient(trusted));
    final value=make();await login(value);await enroll(value,delivery);
    expect(value.possessionAcknowledged,isTrue);expect(calls,1);expect(ackBearers,[token(successorSid)]);
  });
  test('overlapping login/enrollment cannot replace the held session lease or invoke another exchange',() async {
    final value=make(),delivery=FixtureDelivery();await login(value);
    final started=Completer<void>(),release=Completer<void>();
    beforeAdoptedUser=(call) async {if(call==1){started.complete();await release.future;}};
    final pending=enroll(value,delivery);await started.future;
    expect(value.actorId,isNull);expect(value.phase,AppleOwnedSessionPhase.adopting);
    await expectLater(login(value),throwsStateError);await expectLater(enroll(value,FixtureDelivery()),throwsStateError);
    release.complete();await pending;
    expect(value.possessionAcknowledged,isTrue);expect(delivery.calls,1);expect(applicationClients,1);
  });
  for(final cause in ['history','background','dispose','signout']){
    test('$cause fences actual SDK adoption before a late getUser response can publish state or ACK',() async {
      final value=make(),delivery=FixtureDelivery();await login(value);
      final started=Completer<void>(),release=Completer<void>();
      beforeAdoptedUser=(call) async {if(call==1){started.complete();await release.future;}};
      final result=expectLater(enroll(value,delivery),throwsStateError);await started.future;
      switch(cause){
        case'history':
          extra.add(AuthState(AuthChangeEvent.signedIn,Session.fromJson(jsonDecode(jsonEncode(initialSession(uid:other))))));
          extra.add(AuthState(AuthChangeEvent.signedIn,Session.fromJson(jsonDecode(jsonEncode(initialSession())))));
        case'background':value.didChangeAppLifecycleState(AppLifecycleState.paused);
        case'dispose':await value.dispose();
        case'signout':await expectLater(value.signOut(),throwsStateError);
      }
      await result.timeout(const Duration(seconds:1));
      expect(value.actorId,isNull);expect(value.ownedSessionAdopted,isFalse);expect(ackBearers,isEmpty);
      release.complete();await Future<void>.delayed(const Duration(milliseconds:30));
      expect(value.actorId,isNull);expect(ackBearers,isEmpty);expect(delivery.calls,1);
      expect(requests.where((r)=>r.contains('/token:')),hasLength(1));
    });
  }
  test('SDK adoption timeout retires the private client, consumes late completion, and never restores original token',() async {
    final value=make(operationTimeout:const Duration(milliseconds:300)),delivery=FixtureDelivery();await login(value);
    final started=Completer<void>(),release=Completer<void>();
    beforeAdoptedUser=(call) async {if(call==1){started.complete();await release.future;}};
    final result=expectLater(enroll(value,delivery),throwsStateError);await started.future;
    await result;expect(value.phase,AppleOwnedSessionPhase.fenced);expect(value.actorId,isNull);
    release.complete();await Future<void>.delayed(const Duration(milliseconds:30));
    expect(ackBearers,isEmpty);await expectLater(login(value),throwsStateError);
    expect(requests.where((r)=>r.contains('/token:')),hasLength(1));
  });
  test('ACK result loss preserves the verified owned successor and retries only its idempotent possession ACK',() async {
    final value=make(),delivery=FixtureDelivery();await login(value);
    var calls=0;
    acknowledge=(request,bearer) async {calls++;ackBearers.add(bearer);if(calls==1){throw StateError('synthetic ACK response lost');}return ack();};
    await expectLater(enroll(value,delivery),throwsStateError);
    expect(value.phase,AppleOwnedSessionPhase.adoptedAwaitingAck);expect(value.actorId,actor);
    expect(value.ownedSessionAdopted,isTrue);expect(value.possessionAcknowledged,isFalse);
    final writes=requests.where((r)=>r.contains('/token:')).length;
    await value.retryPossessionAck();
    expect(value.possessionAcknowledged,isTrue);expect(ackBearers,[token(successorSid),token(successorSid)]);
    expect(delivery.calls,1);expect(requests.where((r)=>r.contains('/token:')).length,writes);
  });
  test('ACK timeout/late reply never confirms adoption and retry never replays enrollment or SDK setSession',() async {
    final value=make(ackTimeout:const Duration(milliseconds:80)),delivery=FixtureDelivery();await login(value);
    final reply=Completer<Map<String,dynamic>>();var count=0;
    acknowledge=(request,bearer){ackBearers.add(bearer);count++;return count==1?reply.future:Future.value(ack());};
    await expectLater(enroll(value,delivery),throwsStateError);
    expect(value.phase,AppleOwnedSessionPhase.adoptedAwaitingAck);expect(value.possessionAcknowledged,isFalse);
    reply.complete(ack());await Future<void>.delayed(Duration.zero);expect(value.possessionAcknowledged,isFalse);
    final adoptedUsers=adoptedUserRequests;
    await value.retryPossessionAck();expect(value.possessionAcknowledged,isTrue);
    expect(adoptedUserRequests,adoptedUsers+1,reason:'one getUser revalidation, not another SDK setSession');expect(delivery.calls,1);
  });
  test('changed Apple subject during real SDK adoption fences without ACK',() async {
    final value=make(),delivery=FixtureDelivery();await login(value);
    applicationAppleSubject='different-apple';
    await expectLater(enroll(value,delivery),throwsStateError);
    expect(value.phase,AppleOwnedSessionPhase.fenced);expect(value.actorId,isNull);expect(ackBearers,isEmpty);
  });
  for(final changed in ['company','google']){
    test('$changed drift after isolated preparation rejects actual SDK adoption before ACK',() async {
      final value=make(),delivery=FixtureDelivery();await login(value);
      beforeAdoptedUser=(call) async {if(call==1){if(changed=='company'){applicationCompany=other;}else{applicationGoogleSubject='changed-google';}}};
      await expectLater(enroll(value,delivery),throwsStateError);
      expect(value.phase,AppleOwnedSessionPhase.fenced);expect(value.actorId,isNull);expect(ackBearers,isEmpty);
    });
  }
  test('foreign successor envelope cannot reach owned SDK adoption or ACK',() async {
    final value=make(),delivery=FixtureDelivery()..payload=()=>{...envelope(),'user_id':other};await login(value);
    await expectLater(enroll(value,delivery),throwsStateError);
    expect(adoptedUserRequests,0);expect(value.phase,AppleOwnedSessionPhase.fenced);expect(ackBearers,isEmpty);
  });
  test('ACK protocol cannot promote possession into durable/global adoption or bind a different request',() async {
    for(final wrong in [{...ack(),'application_adoption_confirmed':true},{...ack(),'request_id':other}]){
      final value=make(),delivery=FixtureDelivery();await login(value);
      acknowledge=(request,bearer) async=>wrong;
      await expectLater(enroll(value,delivery),throwsStateError);
      expect(value.phase,AppleOwnedSessionPhase.adoptedAwaitingAck);expect(value.possessionAcknowledged,isFalse);
      await value.dispose();
    }
  });
  test('normal local signout is serialized after confirmed adoption and never uses global scope',() async {
    final value=make(),delivery=FixtureDelivery();await login(value);await enroll(value,delivery);await value.signOut();
    expect(value.phase,AppleOwnedSessionPhase.signedOut);expect(value.actorId,isNull);
    expect(requests.where((r)=>r.contains('/logout:')),hasLength(1));expect(ackBearers,hasLength(1));
  });
}
