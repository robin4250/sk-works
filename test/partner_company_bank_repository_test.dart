import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/domain/partner_company_bank_account.dart';
import 'package:sk_works/features/people/partner_company_bank_repository.dart';
import 'package:sk_works/features/people/partner_company_bank_page.dart';
import 'package:sk_works/features/people/people_cloud_repository.dart';
import 'package:sk_works/features/auth/app_auth_mutation_gateway.dart';
import 'package:sk_works/features/auth/app_auth_logout_persistence.dart';

const company='10000000-0000-4000-8000-000000000001',partner='10000000-0000-4000-8000-000000000002',actor='10000000-0000-4000-8000-000000000003',sid='10000000-0000-4000-8000-000000000004';
Map<String,dynamic> bank([int version=1])=>{'schema':1,'company_id':company,'partner_company_id':partner,'bank_version':version,'bank_name':'検証銀行','branch_name':'本店','account_type':'普通','account_number':'0000123','account_holder':'テストカイシャ'};
Map<String,dynamic> session({String sessionId=sid}){
 String part(Object value)=>base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=','');
 return {'access_token':'${part({'alg':'HS256'})}.${part({'sub':actor,'session_id':sessionId,'role':'authenticated','exp':4102444800})}.${base64Url.encode(List.filled(32,7)).replaceAll('=','')}',
 'refresh_token':'synthetic','expires_in':3600,'token_type':'bearer','user':{'id':actor,'aud':'authenticated','is_anonymous':false,'app_metadata':{},'user_metadata':{},'created_at':'2026-01-01T00:00:00Z'}};
}
PersonnelPrivacySession privacy(String? Function() actorNow)=>PersonnelPrivacySession(actor:actor,company:company,currentActor:actorNow,
 load:()async=>const PersonnelPrivacySnapshot(actor:actor,company:company,role:'manager',canManage:true,records:[]));
class _Api {
 late SupabaseClient client;late PersonnelPrivacySession scope;late PartnerCompanyBankRepository repo;
 final calls=<http.Request>[];bool available=true,foreign=false;Completer<http.Response>? held;
 Future<void> open()async{
  client=SupabaseClient('https://partner-bank-fixture.invalid','synthetic-public',authOptions:const AuthClientOptions(autoRefreshToken:false),httpClient:MockClient((request)async{
   calls.add(request);if(request.url.path.endsWith('/logout')){return http.Response('',204);}
   expect(request.url.path,startsWith('/rest/v1/rpc/'));expect(request.headers.entries.where((entry)=>entry.key.toLowerCase()=='authorization').single.value,'Bearer ${session()['access_token']}');
   final body=jsonDecode(request.body) as Map;expect(body['p_company'],company);expect(body['p_partner'],partner);
   if(held!=null){return held!.future;}
   final raw=request.url.path.endsWith('save_partner_company_bank')?bank((body['p_expected_version'] as int)+1):{'available':available,'company_id':foreign?partner:company,'partner_company_id':partner,'version':0,'bank':null};
   return http.Response(jsonEncode(raw),200,headers:{'content-type':'application/json'});
  }));await client.auth.setInitialSession(jsonEncode(session()));scope=privacy(()=>client.auth.currentUser?.id);
  repo=PartnerCompanyBankRepository(client,privacySession:scope,expectedCompany:company,partnerCompanyId:partner);
 }
 Future<void> close()async{repo.dispose();scope.dispose();await client.dispose();}
}
class _HeldLogout implements AppLogoutPersistenceFence {
 final held=Completer<void>();@override bool get blocked=>false;
 @override Future<void> persistIntent()=>held.future;
 @override Future<void> confirmLocalRemoval()async{}
 @override Future<void> releaseFence(bool Function() confirmed)async{}
}
class _WidgetRepository extends ChangeNotifier implements PartnerCompanyBankRepository {
 bool current=true;bool available=true;PartnerCompanyBankAccount? saved;
 @override bool get isCurrent=>current;
 @override Future<PartnerCompanyBankWorkspace> load()async=>PartnerCompanyBankWorkspace(available:available,version:available?1:0,bank:available?PartnerCompanyBankAccount.fromJson(bank()):null);
 @override Future<PartnerCompanyBankAccount> save({required int expectedVersion,required PartnerCompanyBankAccount bank})async {saved=bank;return bank;}
 void invalidate(){current=false;notifyListeners();}
 @override dynamic noSuchMethod(Invocation invocation)=>super.noSuchMethod(invocation);
}
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 test('exact scoped SDK RPC reads readiness and writes 7-digit supplier bank snapshot',()async{
  final f=_Api();await f.open();try{
   expect((await f.repo.load()).available,true);
   final result=await f.repo.save(expectedVersion:0,bank:PartnerCompanyBankAccount.fromJson(bank()));expect(result.accountNumber,'0000123');
   final body=jsonDecode(f.calls.last.body) as Map;expect(body['p_expected_version'],0);expect(body['p_bank'],PartnerCompanyBankAccount.fromJson(bank()).bankFields);
   expect(body['p_request'],matches(RegExp(r'^[0-9a-f-]{36}$')));expect(body.containsKey('worker_id'),false);
  }finally{await f.close();}
 });
 test('OFF capability and foreign response cannot be mistaken for registered bank',()async{
  final f=_Api();await f.open();try{f.available=false;expect((await f.repo.load()).available,false);f.foreign=true;await expectLater(f.repo.load(),throwsA(anything));}finally{await f.close();}
 });
 test('fresh same-UID SID change rejects late bank data and cannot adopt a new owner',()async{
  final f=_Api();await f.open();try{
   f.held=Completer<http.Response>();final result=f.repo.load();final rejected=expectLater(result,throwsA(anything));
   for(var attempt=0;attempt<40&&f.calls.isEmpty;attempt++){await Future<void>.delayed(Duration.zero);}
   expect(f.calls,isNotEmpty);
   await f.client.auth.setInitialSession(jsonEncode(session(sessionId:partner)));
   f.held!.complete(http.Response(jsonEncode({'available':true,'company_id':company,'partner_company_id':partner,'version':0,'bank':null}),200,headers:{'content-type':'application/json'}));
   await rejected;await expectLater(f.repo.load(),throwsA(anything));expect(f.calls,hasLength(1));
  }finally{await f.close();}
 });
 test('logout intent with current SDK session refuses a new financial write',()async{
  final f=_Api();await f.open();try{
   await f.repo.load();final held=_HeldLogout();final owner=AppAuthMutationGateway.bindPersistence(f.client,held);final logout=owner.signOut();
   expect(f.client.auth.currentUser?.id,actor);final before=f.calls.length;
   await expectLater(f.repo.save(expectedVersion:0,bank:PartnerCompanyBankAccount.fromJson(bank())),throwsA(anything));expect(f.calls.length,before);
   held.held.complete();await logout;
  }finally{await f.close();}
 });
 test('privacy epoch remains lifetime bound after background and new read',()async{
  final f=_Api();await f.open();try{
   await f.repo.load();final before=f.calls.length;
   f.scope.didChangeAppLifecycleState(AppLifecycleState.paused);f.scope.didChangeAppLifecycleState(AppLifecycleState.resumed);await f.scope.read();
   await expectLater(f.repo.load(),throwsA(anything));expect(f.calls.length,before);
  }finally{await f.close();}
 });
 for(final reason in ['background','auth']){
  testWidgets('private supplier bank fields are destroyed on $reason and never restored',(tester)async{
   final scope=privacy(()=>actor);await scope.read();final repo=_WidgetRepository();
   try{
    await tester.pumpWidget(MaterialApp(home:PartnerCompanyBankPage(privacySession:scope,expectedCompany:company,partnerCompanyId:partner,partnerName:'受注会社',repositoryOverride:repo)));await tester.pumpAndSettle();
    expect(find.text('0000123'),findsOneWidget);expect(find.byType(TextField),findsNWidgets(4));
    if(reason=='background'){scope.didChangeAppLifecycleState(AppLifecycleState.paused);}else{repo.invalidate();}
    await tester.pump();expect(find.byType(TextField,skipOffstage:false),findsNothing);expect(find.text('0000123',skipOffstage:false),findsNothing);
    if(reason=='background'){scope.didChangeAppLifecycleState(AppLifecycleState.resumed);await scope.read();await tester.pump();}
    expect(find.byType(TextField,skipOffstage:false),findsNothing);expect(repo.saved,isNull);
   }finally{await tester.pumpWidget(const SizedBox());scope.dispose();}
  });
 }
 testWidgets('failed foreground personnel read destroys previously shown bank values',(tester)async{
  var fail=false;final scope=PersonnelPrivacySession(actor:actor,company:company,currentActor:()=>actor,load:()async{
   if(fail){throw StateError('fixture permission failure');}return const PersonnelPrivacySnapshot(actor:actor,company:company,role:'manager',canManage:true,records:[]);
  });await scope.read();final repo=_WidgetRepository();
  try{
   await tester.pumpWidget(MaterialApp(home:PartnerCompanyBankPage(privacySession:scope,expectedCompany:company,partnerCompanyId:partner,partnerName:'受注会社',repositoryOverride:repo)));await tester.pumpAndSettle();
   expect(find.text('0000123'),findsOneWidget);fail=true;await scope.refresh();await tester.pump();
   expect(find.byType(TextField,skipOffstage:false),findsNothing);expect(find.text('0000123',skipOffstage:false),findsNothing);
  }finally{await tester.pumpWidget(const SizedBox());scope.dispose();}
 });
 testWidgets('selected partner change cannot relabel another supplier bank',(tester)async{
  final scope=privacy(()=>actor);await scope.read();final repo=_WidgetRepository();
  try{
   await tester.pumpWidget(MaterialApp(home:PartnerCompanyBankPage(privacySession:scope,expectedCompany:company,partnerCompanyId:partner,partnerName:'元の受注会社',repositoryOverride:repo)));await tester.pumpAndSettle();
   expect(find.text('0000123'),findsOneWidget);
   await tester.pumpWidget(MaterialApp(home:PartnerCompanyBankPage(privacySession:scope,expectedCompany:company,partnerCompanyId:actor,partnerName:'別の会社',repositoryOverride:repo)));await tester.pump();
   expect(find.byType(TextField,skipOffstage:false),findsNothing);expect(find.text('0000123',skipOffstage:false),findsNothing);
  }finally{await tester.pumpWidget(const SizedBox());scope.dispose();}
 });

}
