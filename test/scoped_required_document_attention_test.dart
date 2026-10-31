import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/home/home_membership_repository.dart';
import 'package:sk_works/features/notifications/scoped_required_document_attention_repository.dart';

const actor='10000000-0000-0000-0000-000000000001';
const company='10000000-0000-0000-0000-000000000002';
const other='10000000-0000-0000-0000-000000000003';
const worker='10000000-0000-0000-0000-000000000004';
const sidA='10000000-0000-0000-0000-000000000005';
const sidB='10000000-0000-0000-0000-000000000006';
class Fixture {
  String sid=sidA;
  String? responseCompany, responseSid;
  bool unavailable=false;
  List<Map<String,dynamic>> members=[{'company_id':company,'role':'owner'}];
  Completer<void>? entered,release;
  final requests=<http.Request>[];
  final expiry=DateTime.now().millisecondsSinceEpoch~/1000+3600;
  late final client=SupabaseClient('https://synthetic.invalid','synthetic-public',
    authOptions:const AuthClientOptions(autoRefreshToken:false),httpClient:MockClient(respond));
  String token(String id){String part(Object v)=>base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=','');
    return '${part({'alg':'HS256'})}.${part({'sub':actor,'role':'authenticated','session_id':id,'exp':expiry,'is_anonymous':false})}.synthetic';}
  Future<void> login(String id)async{sid=id;await client.auth.signInWithPassword(email:'synthetic@example.invalid',password:'synthetic');await Future<void>.delayed(Duration.zero);}
  Future<http.Response> respond(http.Request request)async{
    requests.add(request);Object? value;var status=200;
    switch(request.url.path){
      case '/auth/v1/token': value={'access_token':token(sid),'refresh_token':'synthetic','expires_in':3600,'token_type':'bearer',
        'user':{'id':actor,'aud':'authenticated','role':'authenticated','is_anonymous':false,'email':'synthetic@example.invalid','app_metadata':{},'user_metadata':{},'created_at':'2026-10-31T00:00:00Z'}};
      case '/rest/v1/company_members': value=members;
      case '/rest/v1/companies': value=[{'name':'synthetic company'}];
      case '/rest/v1/user_profiles': value=[{'display_name':'synthetic member'}];
      case '/rest/v1/rpc/current_feature_permissions': value={};
      case '/rest/v1/rpc/current_payroll_adjustment_permissions': value={};
      case '/rest/v1/rpc/current_user_required_document_attention_for_company':
        final capturedSid=sid;entered?.complete();if(release!=null){await release!.future;}
        if(unavailable){status=404;value={'code':'PGRST202','message':'scoped attention unavailable'};}
        else{value={'capability_version':1,'company_id':responseCompany??jsonDecode(request.body)['p_company_id'],'worker_id':worker,
          'actor_id':actor,'session_id':responseSid??capturedSid,'missing_count':0,'missing_names':[],'unknown_count':0,'unknown_names':[]};}
      default: throw StateError('Unexpected endpoint: ${request.url.path}');
    }
    return http.Response(jsonEncode(value),status,headers:{'content-type':'application/json'},request:request);
  }
  Future<Map<String,dynamic>> load({String? selected=company,String? Function()? current})=>
    ScopedRequiredDocumentAttentionRepository(client).load(companyId:selected,currentCompany:current);
}
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 test('scoped endpoint uses explicit company and captured Bearer without legacy fallback',()async{
  final f=Fixture();addTearDown(f.client.dispose);await f.login(sidA);f.requests.clear();
  final value=await f.load();expect(value['company_id'],company);
  expect(f.requests.map((r)=>r.url.path),['/rest/v1/company_members','/rest/v1/rpc/current_user_required_document_attention_for_company']);
  expect(jsonDecode(f.requests.last.body),{'p_company_id':company});
  expect(f.requests.every((r)=>r.headers['Authorization']=='Bearer ${f.token(sidA)}'),isTrue);
 });
 test('multiple memberships require explicit selection and never adopt the first company',()async{
  final f=Fixture()..members=[{'company_id':other,'role':'owner'},{'company_id':company,'role':'owner'}];
  addTearDown(f.client.dispose);await f.login(sidA);f.requests.clear();
  await expectLater(f.load(selected:null),throwsStateError);expect(f.requests.any((r)=>r.url.path.contains('/rpc/')),isFalse);
  expect((await f.load())['company_id'],company);
 });
 test('foreign scope and mismatched company or SID responses fail closed',()async{
  final f=Fixture();addTearDown(f.client.dispose);await f.login(sidA);
  await expectLater(f.load(selected:other),throwsStateError);
  f.responseCompany=other;await expectLater(f.load(),throwsStateError);
  f.responseCompany=null;f.responseSid=sidB;await expectLater(f.load(),throwsStateError);
 });
 test('uninstalled scoped endpoint never silently calls legacy no-argument RPC',()async{
  final f=Fixture()..unavailable=true;addTearDown(f.client.dispose);await f.login(sidA);
  await expectLater(f.load(),throwsA(isA<PostgrestException>()));
  expect(f.requests.any((r)=>r.url.path.endsWith('/current_user_required_document_attention')),isFalse);
 });
 test('old SID response is discarded after same UID SID A B A',()async{
  final f=Fixture()..entered=Completer<void>()..release=Completer<void>();addTearDown(f.client.dispose);await f.login(sidA);
  final pending=f.load();final checked=expectLater(pending,throwsStateError);await f.entered!.future;
  await f.login(sidB);await f.login(sidA);f.release!.complete();await checked;
 });
 test('company change discards a response without changing registered evidence',()async{
  final f=Fixture()..entered=Completer<void>()..release=Completer<void>();addTearDown(f.client.dispose);await f.login(sidA);
  var current=company;final pending=f.load(current:()=>current);final checked=expectLater(pending,throwsStateError);
  await f.entered!.future;current=other;f.release!.complete();await checked;
 });
 test('home identity uses its one authoritative membership and refuses ambiguous default scope',()async{
  final f=Fixture();addTearDown(f.client.dispose);await f.login(sidA);
  final repo=HomeMembershipRepository.forClient(f.client);
  final identity=await repo.loadIdentity();expect(identity.companyId,company);expect(identity.isAdmin,isTrue);
  f.members=[{'company_id':other,'role':'owner'},{'company_id':company,'role':'manager'}];
  await expectLater(repo.loadIdentity(),throwsStateError);
  final selected=await repo.loadIdentity(companyId:company);expect(selected.companyId,company);expect(selected.role,'manager');
  expect(selected.permissions,isEmpty,reason:'legacy default-company permission RPC is not reused across selected companies');
 });
}
