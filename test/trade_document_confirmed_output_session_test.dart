import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/auth/app_auth_mutation_gateway.dart';
import 'package:sk_works/features/shared/trade_document_confirmation_approved_pdf.dart';
import 'package:sk_works/features/shared/trade_document_confirmation_repository.dart';
import 'package:sk_works/features/shared/trade_document_form_session.dart';

const _sidA='20000000-0000-4000-8000-000000000001';
const _sidB='20000000-0000-4000-8000-000000000002';
Map<String,dynamic> _copy(Map value)=>Map<String,dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
Map<String,dynamic> confirmedOutputScope(Map raw)=>{'p_company_id':raw['company_id'],'p_local_document_id':raw['local_document_id'],
  'p_document_revision':raw['document_revision'],'p_kind':raw['kind'],'expected_document_id':raw['document_id']};
class ConfirmedOutputWire extends http.BaseClient{
  ConfirmedOutputWire():envelope=_copy((jsonDecode(File('test/fixtures/trade_document_confirmation_api_synthetic.json').readAsStringSync()) as Map)['received_render'] as Map);
  final Map<String,dynamic> envelope;
  final requests=<http.BaseRequest>[];
  final expiry=DateTime.now().millisecondsSinceEpoch~/1000+3600;
  String sid=_sidA,token='';int nonce=0;
  Completer<void>? holdRender,holdLogout;
  final renderStarted=Completer<void>(),logoutStarted=Completer<void>();
  Iterable<http.BaseRequest> get rpcs=>requests.where((r)=>r.url.path.contains('/rest/v1/rpc/'));
  String jwt(){
    String part(Object value)=>base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=','');
    return '${part({'alg':'HS256','typ':'JWT'})}.${part({'sub':envelope['actor_id'],'session_id':sid,'role':'authenticated','exp':expiry,'synthetic_nonce':nonce})}.${base64Url.encode(List<int>.filled(32,7)).replaceAll('=','')}';
  }
  @override Future<http.StreamedResponse> send(http.BaseRequest request)async{
    requests.add(request);Object? value;
    if(request.url.path.endsWith('/auth/v1/token')){
      token=jwt();value={'access_token':token,'refresh_token':'synthetic-refresh','expires_in':3600,'token_type':'bearer',
        'user':{'id':envelope['actor_id'],'aud':'authenticated','role':'authenticated','created_at':'2026-01-01T00:00:00Z'}};
    }else if(request.url.path.endsWith('/auth/v1/logout')){
      if(!logoutStarted.isCompleted)logoutStarted.complete();await holdLogout?.future;value={};
    }else{
      expect(request.headers['Authorization']??request.headers['authorization'],'Bearer $token');
      if(request.url.path.endsWith('/trade_document_confirmation_contract_version')){value=1;}
      else{
        expect(request.url.path.endsWith('/render_confirmed_trade_document'),isTrue);
        final expected={...confirmedOutputScope(envelope)}..remove('expected_document_id');expected['p_archive']=false;
        expect(jsonDecode((request as http.Request).body),expected);
        if(!renderStarted.isCompleted)renderStarted.complete();await holdRender?.future;value=envelope;
      }
    }
    return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(value))),200,headers:{'content-type':'application/json'},request:request);
  }
}
class ConfirmedOutputFixture{
  final wire=ConfirmedOutputWire();late final client=SupabaseClient('https://synthetic.invalid','synthetic-public',httpClient:wire,authOptions:const AuthClientOptions(autoRefreshToken:false));
  SupabaseTradeConfirmationRepository? repository;
  Future<void> login()async{await client.auth.signInWithPassword(email:'synthetic@example.invalid',password:'synthetic-password');}
  Future<SupabaseTradeConfirmationRepository> start()async{await login();return repository=SupabaseTradeConfirmationRepository(client);}
  Future<void> close()async{
    if(wire.holdRender?.isCompleted==false)wire.holdRender!.complete();if(wire.holdLogout?.isCompleted==false)wire.holdLogout!.complete();
    await repository?.dispose();await client.dispose();
  }
}
void main(){
  setUp(()=>TestWidgetsFlutterBinding.ensureInitialized().handleAppLifecycleStateChanged(AppLifecycleState.resumed));
  test('actual SDK received render keeps viewer header distinct from foreign issuer and opens exact child scope',()async{
    final f=ConfirmedOutputFixture();addTearDown(f.close);final repo=await f.start();expect(await repo.available(),isTrue);
    final scope=confirmedOutputScope(f.wire.envelope),raw=await repo.render(confirmedOutputScope(f.wire.envelope));
    expect((raw['evidence']['body'] as Map)['issuer_company_id'],isNot(scope['p_company_id']));
    final approved=TradeConfirmationPdf.approvedAttachment(raw,scope,repo.actorId!);expect(approved.payload['issuer_company_id'],raw['evidence']['body']['issuer_company_id']);
    final TradeDocumentFormSession child=await repo.createConfirmedOutputScope(scope,evidence:raw,currentScope:()=>scope);addTearDown(child.dispose);
    expect(child.requireScope,returnsNormally);expect(repo.requireOutputAdmission,returnsNormally);expect(f.wire.rpcs,hasLength(2));
    final captured=f.wire.token;for(final request in f.wire.rpcs){expect(request.headers['Authorization']??request.headers['authorization'],'Bearer $captured');}
  });
  for(final change in ['same SID fresh sign-in','different SID','same SID refreshed token']){
    test('entry history rejects $change before capability or child creation can dispatch',()async{
      final f=ConfirmedOutputFixture();addTearDown(f.close);final repo=await f.start();
      // No deliberate delay: the initial cached replay cannot swallow this event.
      if(change=='different SID')f.wire.sid=_sidB;
      if(change=='same SID refreshed token'){f.wire.nonce++;await f.client.auth.refreshSession();}else{await f.login();}
      await expectLater(repo.available(),throwsStateError);
      final scope=confirmedOutputScope(f.wire.envelope);await expectLater(repo.createConfirmedOutputScope(scope,evidence:f.wire.envelope,currentScope:()=>scope),throwsStateError);
      expect(f.wire.rpcs,isEmpty);
    });
  }
  test('pending gateway logout intent retires factory and listener before SDK signOut reply',()async{
    final f=ConfirmedOutputFixture();addTearDown(f.close);final repo=await f.start();expect(await repo.available(),isTrue);
    var notices=0;repo.outputAdmissionChanges.addListener(()=>notices++);
    f.wire.holdLogout=Completer<void>();final logout=AppAuthMutationGateway.forClient(f.client).signOut();
    expect(f.wire.logoutStarted.isCompleted,isFalse);expect(f.client.auth.currentSession?.accessToken,f.wire.token);
    expect(repo.requireOutputAdmission,throwsStateError);await f.wire.logoutStarted.future;
    final scope=confirmedOutputScope(f.wire.envelope);await expectLater(repo.createConfirmedOutputScope(scope,evidence:f.wire.envelope,currentScope:()=>scope),throwsStateError);
    expect(notices,greaterThan(0));expect(f.wire.rpcs,hasLength(1));f.wire.holdLogout!.complete();await logout;
  });
  test('held actual SDK render cannot return late evidence across same-UID session change',()async{
    final f=ConfirmedOutputFixture();addTearDown(f.close);final repo=await f.start();expect(await repo.available(),isTrue);
    final scope=confirmedOutputScope(f.wire.envelope);final child=await repo.createConfirmedOutputScope(scope,evidence:f.wire.envelope,currentScope:()=>scope);addTearDown(child.dispose);
    var notices=0;child.addListener(()=>notices++);f.wire.holdRender=Completer<void>();
    final pending=repo.render(scope);
    // Attach a rejection observer before delivering any invalidation.
    final rejected=expectLater(pending,throwsStateError);await f.wire.renderStarted.future;
    f.wire.sid=_sidB;await f.login();f.wire.holdRender!.complete();await rejected;
    expect(child.requireScope,throwsStateError);expect(notices,greaterThan(0));expect(f.wire.rpcs,hasLength(2));
  });
  test('observed viewer target change remains terminal even after restoring its descriptor',()async{
    final f=ConfirmedOutputFixture();addTearDown(f.close);final repo=await f.start();final scope=confirmedOutputScope(f.wire.envelope);Map<String,dynamic>? current=_copy(scope);
    final child=await repo.createConfirmedOutputScope(scope,evidence:f.wire.envelope,currentScope:()=>current);addTearDown(child.dispose);
    current={...scope,'p_document_revision':2};expect(child.requireScope,throwsStateError);current=_copy(scope);expect(child.requireScope,throwsStateError);
    expect(repo.requireOutputAdmission,returnsNormally);expect(f.wire.rpcs,isEmpty);
  });
  test('foreign issuer must never replace viewer header and every bound evidence field rejects mismatch',()async{
    final f=ConfirmedOutputFixture();addTearDown(f.close);final repo=await f.start();final raw=f.wire.envelope,scope=confirmedOutputScope(raw);
    for(final replacement in <String,Object>{'company_id':raw['evidence']['body']['issuer_company_id'],'actor_id':'00000000-0000-0000-0000-000000000099',
      'document_id':raw['local_document_id'],'local_document_id':raw['document_id'],'document_revision':2,'kind':'invoice','archive':true}.entries){
      await expectLater(repo.createConfirmedOutputScope(scope,evidence:{...raw,replacement.key:replacement.value},currentScope:()=>scope),throwsFormatException);
    }
    expect(f.wire.rpcs,isEmpty);
  });
}
