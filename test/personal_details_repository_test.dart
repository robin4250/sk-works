import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/profile/personal_details_repository.dart';
import 'package:sk_works/features/people/own_bank_account_repository.dart';
import 'own_bank_account_repository_test.dart' as auth_fixture;
const sid='20000000-0000-4000-8000-000000000001',op='30000000-0000-4000-8000-000000000001';
const digest='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
class Pending implements PersonalDetailsPendingStore {
 Map<String,dynamic>? value;
 @override Future<Map<String,dynamic>?> read(String actor) async=>value;
 @override Future<void> put(String actor,Map<String,dynamic> m) async{value=Map.from(m);}
 @override Future<void> clear(String actor) async{value=null;}
}
class Fixture {
 late SupabaseClient client;late PersonalDetailsRepository repository;final pending=Pending();
 String? updatedAt;
 final requests=<http.Request>[];bool failSave=false,extra=false,reconcileApplied=true;Completer<void>? held,entered;
 Map<String,dynamic> base(int revision)=>{'protocol_version':1,'actor_id':auth_fixture.actor,'session_id':sid,'revision':revision};
 Future<void> init() async {
 client=SupabaseClient('https://personal.invalid','synthetic',authOptions:const AuthClientOptions(autoRefreshToken:false),httpClient:MockClient((r)async{
  requests.add(r);final name=r.url.path.split('/').last;final args=jsonDecode(r.body) as Map;
  expect(args['p_expected_session'],sid);expect(args.containsKey('p_company'),false);expect(args.containsKey('p_worker'),false);
  Map<String,dynamic> body;
  switch(name){
   case 'personal_details_summary_v1':
    if(held!=null){entered!.complete();await held!.future;}
    body={...base(updatedAt==null?0:1),'record_exists':updatedAt!=null,'birth_date':null,'bank_registered':false,'updated_at':updatedAt,if(extra)'unknown':true};
   case 'personal_details_prepare_save_v1':body={...base(0),'operation_id':op,'input_sha256':digest};
   case 'personal_details_save_v1':
    expect(pending.value,isNotNull,reason:'durable ambiguity fence before dispatch');
    if(failSave)throw http.ClientException('synthetic lost ACK');
    body={...base(1),'operation_id':op,'input_sha256':digest,'outcome':'applied'};
   case 'personal_details_reconcile_v1':body={...base(reconcileApplied?1:0),'operation_id':op,'input_sha256':digest,'outcome':reconcileApplied?'applied':'unknown'};
   case 'personal_bank_read_v1':body={...base(0),'bank_account':null};
   default:throw StateError('Unexpected endpoint');
  }
  return http.Response(jsonEncode(body),200,headers:{'content-type':'application/json'},request:r);
 }));
 await client.auth.setInitialSession(jsonEncode(auth_fixture.session(sid)));
 repository=PersonalDetailsRepository.forClient(client,pendingStore:pending);
 }
 Future<void> close() async{await repository.close();await client.dispose();}
}
void main(){
 test('existing summary requires a valid UTC timestamp, not date-only or local offset',()async{
  final f=Fixture();await f.init();addTearDown(f.close);
  for(final invalid in ['2026-11-01','2026-11-01T00:00:00+09:00','2026-02-30T00:00:00Z']){
   f.updatedAt=invalid;await expectLater(f.repository.load(),throwsFormatException);
  }
  f.updatedAt='2026-11-01T00:00:00.000000Z';expect((await f.repository.load()).exists,true);
 });
 test('birthday rejects year zero and invalid calendar days',(){
  expect(personalBirthDateValid('0000-01-01'),false);
  expect(personalBirthDateValid('2001-02-29'),false);
  expect(personalBirthDateValid('2000-02-29'),true);
  expect(personalBirthDateValid('0001-01-01'),true);
 });
 test('verified absent summary has no worker/company lookup and strict unknownkey refuses',()async{
  final f=Fixture();await f.init();addTearDown(f.close);
  final summary=await f.repository.load();expect(summary.exists,false);expect(summary.revision,0);expect(summary.bankRegistered,false);
  f.extra=true;await expectLater(f.repository.load(),throwsFormatException);
 });
 test('prepare exact dirtysubset and opaque digest bind same prooftarget and save receipt',()async{
  final f=Fixture();await f.init();addTearDown(f.close);await f.repository.load();
  final result=await f.repository.save(0,{'birth_date':'1990-01-02'},op,(operation,target)async{
   expect(operation,'personal.details.save');expect(target,{'user_id':auth_fixture.actor,'before_revision':0,'operation_id':op,'input_sha256':digest});return 'b'*64;
  });expect(result,true);expect(f.pending.value,null);
  final args=jsonDecode(f.requests.singleWhere((r)=>r.url.path.endsWith('personal_details_save_v1')).body);
  expect(args['p_changes'],{'birth_date':'1990-01-02'});expect(args['p_input_sha256'],digest);
 });
 test('unknown ACK retains metadata only, blocks repeated save, reconcile applied clears without mutation replay',()async{
  final f=Fixture();await f.init();addTearDown(f.close);await f.repository.load();f.failSave=true;
  await expectLater(f.repository.save(0,{'bank_account':personalBankJson(OwnBankAccountInput(bankName:'Synthetic',branchName:'Synthetic',accountType:'普通',accountNumber:'００００００１',accountHolder:'Synthetic'))},op,(_,_)async=>'b'*64),throwsA(isA<PersonalDetailsUnconfirmed>()));
  expect(f.pending.value!.keys.toSet(),{'actor','sid','before','operation','digest'});expect(jsonEncode(f.pending.value).contains('Synthetic'),false);
  await expectLater(f.repository.save(0,{'birth_date':null},op,(_,_)async=>'b'*64),throwsStateError);
  expect(await f.repository.reconcile(),true);
  expect(f.requests.where((r)=>r.url.path.endsWith('personal_details_save_v1')).length,1);
 });
 test('unknown reconcile never becomes not-applied or clears ambiguity fence',()async{
  final f=Fixture();await f.init();addTearDown(f.close);await f.repository.load();f.failSave=true;f.reconcileApplied=false;
  await expectLater(f.repository.save(0,{'birth_date':null},op,(_,_)async=>'b'*64),throwsA(isA<PersonalDetailsUnconfirmed>()));
  expect(await f.repository.reconcile(),false);expect(f.repository.pendingUnknown,true);expect(f.pending.value,isNotNull);
 });
 test('cancelled proof never dispatches save or reports success',()async{
  final f=Fixture();await f.init();addTearDown(f.close);await f.repository.load();
  expect(await f.repository.save(0,{'birth_date':null},op,(_,_)async=>null),false);
  expect(f.requests.any((r)=>r.url.path.endsWith('personal_details_save_v1')),false);expect(f.pending.value,null);
 });
 test('held reply after SID switch rejected, no stale DTO',()async{
  final f=Fixture();await f.init();addTearDown(f.close);f.held=Completer<void>();f.entered=Completer<void>();
  final pending=f.repository.load();final rejected=expectLater(pending,throwsStateError);await f.entered!.future;
  await f.client.auth.setInitialSession(jsonEncode(auth_fixture.session('20000000-0000-4000-8000-000000000002')));f.held!.complete();await rejected;
 });
 test('old SID pending remains quarantined and cannot reconcile or write under new SID',()async{
  final f=Fixture();await f.init();addTearDown(f.close);f.pending.value={'actor':auth_fixture.actor,'sid':'20000000-0000-4000-8000-000000000002','before':0,'operation':op,'digest':digest};
  await f.repository.load();await expectLater(f.repository.reconcile(),throwsA(isA<PersonalDetailsUnconfirmed>()));expect(f.pending.value,isNotNull);
 });
}
