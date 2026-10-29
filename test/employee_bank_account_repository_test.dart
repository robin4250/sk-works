import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/people/employee_bank_account_repository.dart';
import 'package:sk_works/features/people/own_bank_account_repository.dart';
import 'package:sk_works/features/auth/app_auth_mutation_gateway.dart';
import 'package:sk_works/features/auth/app_auth_logout_persistence.dart';
const actor='10000000-0000-0000-0000-000000000001';
const company='30000000-0000-0000-0000-000000000001';
const worker='40000000-0000-0000-0000-000000000001';
Map<String,dynamic> session(String sid) {
  String part(Object v)=>base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=','');
  return {'access_token':'${part({'alg':'HS256'})}.${part({'sub':actor,'role':'authenticated','session_id':sid,'exp':DateTime.now().millisecondsSinceEpoch ~/ 1000+3600})}.synthetic',
    'refresh_token':'synthetic-$sid','token_type':'bearer','expires_in':3600,
    'user':{'id':actor,'aud':'authenticated','created_at':'2026-10-29T00:00:00Z','app_metadata':<String,dynamic>{},'user_metadata':<String,dynamic>{}}};
}
OwnBankAccountInput input()=>OwnBankAccountInput(bankName:'合成試験銀行',branchName:'SYNTHETIC BRANCH',accountType:'普通',accountNumber:'００００００１',accountHolder:'SYNTHETIC HOLDER');
class Fixture {
  late SupabaseClient client;late EmployeeBankAccountRepository repository;
  final calls=<http.Request>[];
  bool own=false,enabled=true,registered=false,missing=false,denied=false,wrongScope=false,wrongSave=false;
  Future<void> Function()? afterProof;
  Map<String,dynamic> get metadata=>{'worker_id':worker,'company_id':company,'updated_at':registered?'2026-10-29T00:00:00Z':null};
  Future<void> login(String sid)=>client.auth.setInitialSession(jsonEncode(session(sid)));
  int get writes=>calls.where((r)=>r.url.path.endsWith('register_employee_bank_initial')||r.url.path.endsWith('worker_private_bank_accounts')&&r.method=='POST').length;
  static Future<Fixture> create() async {
    final f=Fixture();f.client=SupabaseClient('https://employee-bank-fixture.invalid','public_fixture',
      authOptions:const AuthClientOptions(autoRefreshToken:false),httpClient:MockClient((r) async {
        f.calls.add(r);dynamic value;var status=200;
        switch(r.url.path.split('/').last) {
          case 'company_members':value={'company_id':company,'user_id':actor};
          case 'workers':value={'id':worker,'company_id':company,'user_id':f.own?actor:'10000000-0000-0000-0000-000000000002','status':'active'};
          case 'employee_bank_initial_capability':
            if(f.missing){status=404;value={'code':'PGRST202','message':'Could not find public.employee_bank_initial_capability'};}
            else if(f.denied){status=403;value={'code':'42501','message':'Synthetic permission denied'};}
            else value={'protocol':'sko-employee-bank-initial-v1','enabled':f.enabled,'registered':f.registered,...f.metadata,if(f.wrongScope)'worker_id':actor};
          case 'reauthenticate-operation':
            final body=jsonDecode(r.body) as Map;await f.afterProof?.call();
            value={'protocol':'sko-reauthentication-v1','operation':body['operation'],'target':body['target'],'proof':'a'*64,'expiresAt':DateTime.now().add(const Duration(seconds:90)).toUtc().toIso8601String()};
          case 'register_employee_bank_initial':
            f.registered=true;value={'protocol':'sko-employee-bank-initial-v1','registered':true,...f.metadata,if(f.wrongSave)'company_id':actor};
          case 'worker_private_bank_accounts':
            if(r.method=='POST')f.registered=true;value=f.registered?f.metadata:null;
          default:throw StateError('Unexpected synthetic endpoint');
        }
        return http.Response(jsonEncode(value),status,headers:{'content-type':'application/json'},request:r);
      }));
    await f.login('20000000-0000-0000-0000-000000000001');
    f.repository=EmployeeBankAccountRepository.forClient(f.client,companyId:company,workerId:worker);return f;
  }
  Future<void> close() async {await repository.close();await client.dispose();}
}
class LogoutFence implements AppLogoutPersistenceFence {
  final finish=Completer<void>();@override bool blocked=false;
  @override Future<void> persistIntent() async {blocked=true;await finish.future;throw StateError('Synthetic logout marker failure');}
  @override Future<void> confirmLocalRemoval() async=>throw StateError('Unexpected');
  @override Future<void> releaseFence(bool Function() confirmed) async=>throw StateError('Unexpected');
}
void main(){
  test('UTF8 canonical digest matches independent Node and actual PostgreSQL vector',(){
    expect(employeeBankInitialDigest(company,worker,input()),'8db7a7fc9af6815f800a1d6a4eb3b95af2e59c245795ba988f0ab51e1793df3e');
  });
  test('selected other employee uses exact capability/proof/RPC payload and captured bearer, never own table or current-worker fallback',() async {
    final f=await Fixture.create();addTearDown(f.close);final bearer='Bearer ${f.client.auth.currentSession!.accessToken}';
    final saved=await f.repository.register(input(),requestPassword:() async=>'synthetic-primary');
    expect(saved.workerId,worker);expect(saved.companyId,company);expect(saved.registered,isTrue);expect(saved.self,isFalse);expect(f.repository.selfGateway,isNull);expect(f.writes,1);
    final sent=f.calls.singleWhere((r)=>r.url.path.endsWith('register_employee_bank_initial'));
    expect(jsonDecode(sent.body),{'p_company_id':company,'p_worker_id':worker,'p_proof':'a'*64,
      'p_bank_data':{'bank_name':'合成試験銀行','branch_name':'SYNTHETIC BRANCH','account_type':'普通','account_number':'0000001','account_holder':'SYNTHETIC HOLDER'}});
    final proof=f.calls.singleWhere((r)=>r.url.path.endsWith('reauthenticate-operation'));
    expect((jsonDecode(proof.body) as Map)['target'],{'company_id':company,'worker_id':worker,'input_sha256':employeeBankInitialDigest(company,worker,input())});
    for(final call in f.calls){expect(call.headers['Authorization'],bearer);expect(['PUT','PATCH','DELETE'].contains(call.method),isFalse);}
    expect(f.calls.any((r)=>r.url.path.contains('worker_private_bank_accounts')||r.url.path.contains('ensure_current_user_worker')),isFalse);
  });
  for(final condition in ['OFF','existing','missing','wrongscope']) {
    test('$condition blocks before password with no direct fallback',() async {
      final f=await Fixture.create();addTearDown(f.close);f.enabled=condition!='OFF';f.registered=condition=='existing';f.missing=condition=='missing';f.wrongScope=condition=='wrongscope';var passwords=0;
      await expectLater(f.repository.register(input(),requestPassword:() async {passwords++;return 'synthetic-primary';}),throwsStateError);
      expect(passwords,0);expect(f.writes,0);expect(f.calls.any((r)=>r.url.path.endsWith('worker_private_bank_accounts')),isFalse);
    });
  }
  test('permission denial remains unknown instead of claiming unregistered or issuing proof',() async {
    final f=await Fixture.create();addTearDown(f.close);f.denied=true;
    await expectLater(f.repository.load(),throwsA(isA<PostgrestException>()));expect(f.writes,0);
  });
  test('same UID SID A to B to A while collecting password rejects before proof or insert',() async {
    final f=await Fixture.create();addTearDown(f.close);
    await expectLater(f.repository.register(input(),requestPassword:() async {
      await f.login('20000000-0000-0000-0000-000000000002');await f.login('20000000-0000-0000-0000-000000000001');return 'synthetic-primary';
    }),throwsStateError);
    expect(f.writes,0);expect(f.calls.any((r)=>r.url.path.endsWith('reauthenticate-operation')),isFalse);
  });
  test('real capability is checked again after proof and prevents write if disabled',() async {
    final f=await Fixture.create();addTearDown(f.close);f.afterProof=() async {f.enabled=false;};
    await expectLater(f.repository.register(input(),requestPassword:() async=>'synthetic-primary'),throwsStateError);expect(f.writes,0);
  });
  test('mismatched save response is unknown and never retries or overwrites',() async {
    final f=await Fixture.create();addTearDown(f.close);f.wrongSave=true;
    await expectLater(f.repository.register(input(),requestPassword:() async=>'synthetic-primary'),throwsStateError);expect(f.writes,1);
    await expectLater(f.repository.register(input(),requestPassword:() async=>'synthetic-primary'),throwsStateError);expect(f.writes,1);
  });
  test('self API is available only when the selected worker user matches actor, with selected IDs retained',() async {
    final f=await Fixture.create();addTearDown(f.close);f.own=true;
    final state=await f.repository.load();expect(state.self,isTrue);final own=f.repository.selfGateway!;
    await own.register(input());expect(f.writes,1);
    final sent=f.calls.singleWhere((r)=>r.url.path.endsWith('worker_private_bank_accounts')&&r.method=='POST');
    expect((jsonDecode(sent.body) as Map)['worker_id'],worker);expect((jsonDecode(sent.body) as Map)['company_id'],company);
    expect(f.calls.any((r)=>r.url.path.endsWith('register_employee_bank_initial')),isFalse);
  });
  test('pending/failed logout with unchanged SDK token denies all new bank reads and writes',() async {
    final f=await Fixture.create();addTearDown(f.close);await f.repository.load();f.calls.clear();
    final fence=LogoutFence(),owner=AppAuthMutationGateway.forClient(f.client);AppAuthMutationGateway.bindPersistence(f.client,fence);
    final token=f.client.auth.currentSession!.accessToken;final stopped=expectLater(owner.signOut(),throwsStateError);
    try {await expectLater(f.repository.load(),throwsStateError);await expectLater(f.repository.register(input(),requestPassword:() async=>'synthetic-primary'),throwsStateError);expect(f.calls,isEmpty);}
    finally {fence.finish.complete();await stopped;}
    expect(f.client.auth.currentSession!.accessToken,token);await expectLater(f.repository.load(),throwsStateError);expect(f.calls,isEmpty);
  });
}
