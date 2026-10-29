import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/people/own_bank_account_repository.dart';

const actor='10000000-0000-0000-0000-000000000001';
const company='30000000-0000-0000-0000-000000000001';
const worker='40000000-0000-0000-0000-000000000001';
Map<String,dynamic> session(String sid) {
  String part(Object v)=>base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=','');
  return {'access_token':'${part({'alg':'HS256'})}.${part({'sub':actor,'role':'authenticated','session_id':sid,'exp':DateTime.now().millisecondsSinceEpoch ~/ 1000+3600})}.synthetic',
    'refresh_token':'synthetic-$sid','token_type':'bearer','expires_in':3600,
    'user':{'id':actor,'aud':'authenticated','created_at':'2026-10-29T00:00:00Z','app_metadata':<String,dynamic>{},'user_metadata':<String,dynamic>{}}};
}
OwnBankAccountInput input({String number='００００００１',String type='普通'})=>OwnBankAccountInput(
  bankName:' SYNTHETIC BANK ',branchName:' SYNTHETIC BRANCH ',accountType:type,
  accountNumber:number,accountHolder:' SYNTHETIC HOLDER ');
class Fixture {
  late SupabaseClient client;
  late OwnBankAccountRepository repository;
  final requests=<http.Request>[];
  bool existing=false,denyRead=false,wrongWorker=false,missingMember=false,wrongResponse=false;
  Completer<void>? metadataWait,writeWait;
  Future<void> Function()? duringInsert;
  Map<String,dynamic> get metadata=>{'worker_id':worker,'company_id':company,'updated_at':'2026-10-29T00:00:00Z'};
  Future<void> login(String sid)=>client.auth.setInitialSession(jsonEncode(session(sid)));
  int get writes=>requests.where((r)=>r.method=='POST').length;
  static Future<Fixture> create() async {
    final f=Fixture();
    f.client=SupabaseClient('https://bank-fixture.invalid','public_fixture',
      authOptions:const AuthClientOptions(autoRefreshToken:false),
      httpClient:MockClient((r) async {
        f.requests.add(r); Object? body; var status=200;
        switch(r.url.path.split('/').last) {
          case 'company_members': body=f.missingMember ? null : {'company_id':company,'user_id':actor};
          case 'workers': body={'id':worker,'company_id':company,'user_id':f.wrongWorker ? 'other-synthetic-user' : actor};
          case 'worker_private_bank_accounts':
            if(r.method=='POST') {
              if(f.writeWait!=null) await f.writeWait!.future;
              await f.duringInsert?.call(); f.existing=true;
              body={...f.metadata,if(f.wrongResponse) 'company_id':'other-synthetic-company'};
            } else {
              if(f.metadataWait!=null) await f.metadataWait!.future;
              if(f.denyRead) {status=403;body={'code':'42501','message':'Synthetic permission denied'};}
              else {body=f.existing ? f.metadata : null;}
            }
          default: throw StateError('Unexpected synthetic endpoint');
        }
        return http.Response(jsonEncode(body),status,headers:{'content-type':'application/json'},request:r);
      }));
    await f.login('sid-a');
    f.repository=OwnBankAccountRepository.forClient(f.client,workerId:worker,companyId:company);
    return f;
  }
  Future<void> close() async {await repository.close();await client.dispose();}
}
void main() {
  test('7-digit text preserves leading zeroes and normalizes fullwidth digits without weakening table checks',() {
    expect(input().isValid,isTrue);expect(input().accountNumber,'0000001');
    for(final n in ['123456','12345678','123 456','1e00001','12-3456']) {expect(input(number:n).isValid,isFalse);}
    expect(input(type:'その他').isValid,isFalse);
    expect(input(number:'0000001').accountNumber,'0000001');
  });
  test('actual SDK sends self-scoped captured bearer, exact private column names, insert only and metadata only',() async {
    final f=await Fixture.create();addTearDown(f.close);
    final bearer='Bearer ${f.client.auth.currentSession!.accessToken}';
    final state=await f.repository.register(input());expect(state.registered,isTrue);expect(f.writes,1);
    final sent=f.requests.singleWhere((r)=>r.method=='POST');
    expect(jsonDecode(sent.body),{'worker_id':worker,'company_id':company,'bank_name':'SYNTHETIC BANK',
      'branch_name':'SYNTHETIC BRANCH','account_type':'普通','account_number':'0000001','account_holder':'SYNTHETIC HOLDER'});
    for(final r in f.requests) {expect(r.headers['Authorization'],bearer);expect(['PATCH','PUT','DELETE'].contains(r.method),isFalse);}
    for(final r in f.requests.where((r)=>r.url.path.endsWith('worker_private_bank_accounts'))) {
      expect(r.url.queryParameters['select'],'worker_id,company_id,updated_at');
      if(r.method=='GET') {expect(r.url.queryParameters['worker_id'],'eq.$worker');expect(r.url.queryParameters['company_id'],'eq.$company');}
    }
    expect(sent.headers['Prefer']?.contains('resolution=merge-duplicates'),isNot(true));
  });
  test('existing account metadata reports registered without reading contents or overwriting',() async {
    final f=await Fixture.create();addTearDown(f.close);f.existing=true;
    expect((await f.repository.load()).registered,isTrue);
    await expectLater(f.repository.register(input()),throwsStateError);expect(f.writes,0);
  });
  test('read denial remains unknown and never turns into an empty account or write',() async {
    final f=await Fixture.create();addTearDown(f.close);f.denyRead=true;
    await expectLater(f.repository.load(),throwsA(isA<PostgrestException>()));
    await expectLater(f.repository.register(input()),throwsA(isA<PostgrestException>()));expect(f.writes,0);
  });
  for(final boundary in ['worker','member']) {
    test('mismatched $boundary fails before private account read or insert',() async {
      final f=await Fixture.create();addTearDown(f.close);
      f.wrongWorker=boundary=='worker';f.missingMember=boundary=='member';
      await expectLater(f.repository.register(input()),throwsStateError);
      expect(f.requests.any((r)=>r.url.path.endsWith('worker_private_bank_accounts')),isFalse);expect(f.writes,0);
    });
  }
  test('same UID SID A to B to A during metadata invalidates permanently and never inserts',() async {
    final f=await Fixture.create();addTearDown(f.close);f.metadataWait=Completer<void>();
    final pending=f.repository.register(input());
    for(var attempt=0;attempt<1000 && !f.requests.any((r)=>r.url.path.endsWith('worker_private_bank_accounts'));attempt++) {await Future<void>.delayed(const Duration(milliseconds:1));}
    expect(f.requests.any((r)=>r.url.path.endsWith('worker_private_bank_accounts')),isTrue);
    await f.login('sid-b');await f.login('sid-a');f.metadataWait!.complete();
    await expectLater(pending,throwsStateError);expect(f.writes,0);expect(f.repository.isCurrent,isFalse);
  });
  test('late insert response after SID change is not success and never triggers a second write',() async {
    final f=await Fixture.create();addTearDown(f.close);
    f.duringInsert=() async {await f.login('sid-b');await f.login('sid-a');};
    await expectLater(f.repository.register(input()),throwsStateError);expect(f.writes,1);
    await expectLater(f.repository.register(input()),throwsStateError);expect(f.writes,1);
  });
  test('mismatched returned company is unconfirmed and performs no fallback update',() async {
    final f=await Fixture.create();addTearDown(f.close);f.wrongResponse=true;
    await expectLater(f.repository.register(input()),throwsStateError);expect(f.writes,1);
  });
}
