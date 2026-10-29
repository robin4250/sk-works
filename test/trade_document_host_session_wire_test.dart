import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/auth/app_auth_mutation_gateway.dart';
import 'package:sk_works/features/shared/trade_document_attachment_repository.dart';
import 'package:sk_works/features/shared/trade_document_form_session.dart';
import 'package:sk_works/domain/trade_document_form_draft.dart';
import 'package:sk_works/domain/trade_document_terms_snapshot.dart';

const _actor='10000000-0000-0000-0000-000000000001';
const _sidA='20000000-0000-0000-0000-000000000001';
const _sidB='20000000-0000-0000-0000-000000000002';
String _token(String sid) {
  String part(Object v)=>base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=','');
  final signature=base64Url.encode(List<int>.filled(32,7)).replaceAll('=','');
  return '${part({'alg':'HS256','typ':'JWT'})}.${part({'sub':_actor,'session_id':sid,'role':'authenticated','exp':DateTime.now().millisecondsSinceEpoch~/1000+3600})}.$signature';
}
Map<String,dynamic> _body()=>TradeDocumentTermsSnapshot.initialize({
  'version':1,'kind':'acceptance','month':'2026-10','issue_date':'2026-09-30','order_date':'2026-09-30',
  'acceptance_text':'Synthetic acceptance of the 2026-09-30 order',
  'work_name':'Synthetic work','work_address':'Synthetic place','period_start':'2026-10-01','period_end':'2026-10-31',
  'total_amount_yen':110000,'tax_amount_yen':10000,'payment_conditions':'Synthetic terms','notes':'',
  'issuer':{'name':'Synthetic issuer'},'counterparty':{'name':'Synthetic partner'},
  'company_seal_enabled':false,'company_seal_snapshot':{'version':1,'style':'legacy','name':'Synthetic issuer'},
});
class _Wire extends http.BaseClient {
  final requests=<http.BaseRequest>[];
  String sid=_sidA,token='';
  Completer<void>? holdRpc,holdLogout;
  final rpcStarted=Completer<void>();
  final logoutStarted=Completer<void>();
  Map<String,dynamic>? saved;
  Iterable<http.BaseRequest> get rpcs=>requests.where((r)=>r.url.path.contains('/rest/v1/rpc/'));
  @override Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);Object? value;
    if(request.url.path.endsWith('/auth/v1/token')) {
      token=_token(sid);value={'access_token':token,'refresh_token':'synthetic-refresh','expires_in':3600,'token_type':'bearer',
        'user':{'id':_actor,'aud':'authenticated','role':'authenticated','created_at':'2026-01-01T00:00:00Z'}};
    } else if(request.url.path.endsWith('/auth/v1/logout')) {
      if(!logoutStarted.isCompleted)logoutStarted.complete();await holdLogout?.future;value={};
    } else {
      expect(request.url.path.startsWith('/rest/v1/rpc/'),isTrue);
      final data=jsonDecode((request as http.Request).body) as Map<String,dynamic>;
      expect(data['p_kind'],'invoice');expect(data['p_subject'],'30000000-0000-0000-0000-000000000001');expect(data['p_source_revision'],'2026-10-29T00:00:00.000Z');
      if(!rpcStarted.isCompleted)rpcStarted.complete();await holdRpc?.future;
      if(request.url.path.endsWith('/save_trade_document_attachment')) {
        expect(data['p_expected_version'],0);saved=Map<String,dynamic>.from(data['p_payload'] as Map);
        value={'version':1,'payload':saved};
      } else {
        expect(request.url.path.endsWith('/trade_document_attachment_workspace'),isTrue);value={'attachment':null,'source_changed':false};
      }
    }
    return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(value))),200,
      headers:{'content-type':'application/json'},request:request);
  }
}
class _Fixture {
  final wire=_Wire();late final SupabaseClient client=SupabaseClient('https://synthetic.invalid','synthetic-public',
    httpClient:wire,authOptions:const AuthClientOptions(autoRefreshToken:false));
  Future<void> login([String sid=_sidA]) async {wire.sid=sid;await client.auth.signInWithPassword(email:'synthetic@example.invalid',password:'synthetic-password');}
  Future<void> dispose() async {if(wire.holdRpc?.isCompleted==false)wire.holdRpc!.complete();if(wire.holdLogout?.isCompleted==false)wire.holdLogout!.complete();await client.dispose();}
}
Future<Map<String,dynamic>> _load(TradeDocumentAttachmentRepository repository)=>repository.loadWorkspace(
  subjectKind:'invoice',subjectId:'30000000-0000-0000-0000-000000000001',sourceRevision:'2026-10-29T00:00:00.000Z');
void main() {
  setUp(()=>TestWidgetsFlutterBinding.ensureInitialized().handleAppLifecycleStateChanged(AppLifecycleState.resumed));
  test('missing SDK session emits no workspace request',() async {
    final f=_Fixture();addTearDown(f.dispose);
    final repository=TradeDocumentAttachmentRepository(f.client);
    await expectLater(_load(repository),throwsStateError);expect(f.wire.requests,isEmpty);
  });
  test('actual SDK workspace and explicit draft save carry captured bearer and immutable company/seal fields',() async {
    final f=_Fixture();addTearDown(f.dispose);await f.login();
    final scope=TradeDocumentFormSession(f.client);addTearDown(scope.dispose);await scope.ready();
    final repository=TradeDocumentAttachmentRepository(f.client,session:scope);
    expect((await _load(repository))['attachment'],isNull);
    final original=_body(),before=jsonEncode(original);
    final draft=TradeDocumentFormDraft.fromPayload(original,allowAmountEditing:false).withChanges({'work_name':'Explicit edited work'});
    draft.validateForSave();
    final result=await repository.save(subjectKind:'invoice',subjectId:'30000000-0000-0000-0000-000000000001',sourceRevision:'2026-10-29T00:00:00.000Z',expectedVersion:0,payload:draft.payload);
    expect(result.version,1);expect(result.payload['work_name'],'Explicit edited work');expect(jsonEncode(original),before);
    expect(f.wire.saved!['issuer'],original['issuer']);expect(f.wire.saved!['counterparty'],original['counterparty']);
    expect(f.wire.saved!['company_seal_snapshot'],original['company_seal_snapshot']);
    expect(f.wire.saved!['total_amount_yen'],110000);
    expect(f.wire.rpcs,hasLength(2));
    for(final request in f.wire.rpcs) {expect(request.headers['Authorization']??request.headers['authorization'],'Bearer ${f.wire.token}');}
    expect(f.wire.requests.every((r)=>r.url.path.endsWith('/auth/v1/token')||r.url.path.contains('/rest/v1/rpc/')),isTrue);
  });
  for(final nextSid in [_sidA,_sidB]) {
    test('fresh sign-in before ready retires captured host even for same UID sid=$nextSid',() async {
      final f=_Fixture();addTearDown(f.dispose);await f.login();
      final scope=TradeDocumentFormSession(f.client);addTearDown(scope.dispose);
      // No pump/delay: cached SDK replay must never consume a fresh sign-in.
      await f.login(nextSid);await expectLater(scope.ready(),throwsStateError);
      await expectLater(_load(TradeDocumentAttachmentRepository(f.client,session:scope)),throwsStateError);
      expect(f.wire.rpcs,isEmpty);
    });
  }
  test('same UID SID A B A rejects pending response and never retries workspace',() async {
    final f=_Fixture();addTearDown(f.dispose);await f.login();
    final scope=TradeDocumentFormSession(f.client);addTearDown(scope.dispose);await scope.ready();
    f.wire.holdRpc=Completer<void>();final result=_load(TradeDocumentAttachmentRepository(f.client,session:scope));
    final rejected=expectLater(result,throwsA(anyOf(isA<StateError>(),isA<Exception>())));await f.wire.rpcStarted.future;
    await f.login(_sidB);await f.login(_sidA);f.wire.holdRpc!.complete();await rejected;
    expect(scope.isCurrent,isFalse);await expectLater(scope.ready(),throwsStateError);expect(f.wire.rpcs,hasLength(1));
  });
  test('gateway logout intent rejects before SDK logout reply or another RPC',() async {
    final f=_Fixture();addTearDown(f.dispose);await f.login();
    final scope=TradeDocumentFormSession(f.client);addTearDown(scope.dispose);await scope.ready();
    f.wire.holdLogout=Completer<void>();final logout=AppAuthMutationGateway.forClient(f.client).signOut();
    expect(scope.isCurrent,isFalse);await expectLater(_load(TradeDocumentAttachmentRepository(f.client,session:scope)),throwsStateError);
    await f.wire.logoutStarted.future;expect(f.wire.rpcs,isEmpty);f.wire.holdLogout!.complete();await logout;
  });
  test('background and resume reject a pending save result without claiming DB rollback or retry',() async {
    final f=_Fixture();addTearDown(f.dispose);await f.login();
    final scope=TradeDocumentFormSession(f.client);addTearDown(scope.dispose);await scope.ready();
    f.wire.holdRpc=Completer<void>();final result=TradeDocumentAttachmentRepository(f.client,session:scope).save(
      subjectKind:'invoice',subjectId:'30000000-0000-0000-0000-000000000001',sourceRevision:'2026-10-29T00:00:00.000Z',expectedVersion:0,payload:_body());
    final rejected=expectLater(result,throwsA(anyOf(isA<StateError>(),isA<Exception>())));await f.wire.rpcStarted.future;
    TestWidgetsFlutterBinding.ensureInitialized().handleAppLifecycleStateChanged(AppLifecycleState.paused);
    TestWidgetsFlutterBinding.ensureInitialized().handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    f.wire.holdRpc!.complete();await rejected;expect(scope.isCurrent,isFalse);
    await expectLater(scope.ready(),throwsStateError);expect(f.wire.rpcs,hasLength(1));
  });
  test('observed target change is terminal and foreign client cannot borrow the host session',() async {
    final f=_Fixture(),other=_Fixture();addTearDown(f.dispose);addTearDown(other.dispose);await f.login();
    var target='company-A/document-A';final scope=TradeDocumentFormSession(f.client,target:target,currentTarget:()=>target);addTearDown(scope.dispose);await scope.ready();
    expect(()=>TradeDocumentAttachmentRepository(other.client,session:scope),throwsArgumentError);
    target='company-B/document-B';expect(scope.requireScope,throwsStateError);target='company-A/document-A';expect(scope.requireScope,throwsStateError);
    await expectLater(_load(TradeDocumentAttachmentRepository(f.client,session:scope)),throwsStateError);expect(f.wire.rpcs,isEmpty);
  });
  test('disposed host rejects in-flight late workspace and cannot emit another request',() async {
    final f=_Fixture();addTearDown(f.dispose);await f.login();final scope=TradeDocumentFormSession(f.client);await scope.ready();
    f.wire.holdRpc=Completer<void>();final result=_load(TradeDocumentAttachmentRepository(f.client,session:scope));
    final rejected=expectLater(result,throwsA(anyOf(isA<StateError>(),isA<Exception>())));await f.wire.rpcStarted.future;
    scope.dispose();scope.dispose();f.wire.holdRpc!.complete();await rejected;
    await expectLater(_load(TradeDocumentAttachmentRepository(f.client,session:scope)),throwsStateError);expect(f.wire.rpcs,hasLength(1));
  });
}
