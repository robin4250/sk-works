// ignore_for_file: depend_on_referenced_packages
// HTTP is supplied by the pinned Supabase dependency in this application.
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/people/people_cloud_repository.dart';
import 'package:sk_works/features/people/people_page.dart';
import 'package:sk_works/features/people/employee_personnel_detail_page.dart';
import 'package:sk_works/features/people/employee_personnel_print_page.dart';
import 'package:sk_works/features/people/employee_personnel_edit_page.dart';
import 'package:sk_works/features/people/company_document_exchange_repository.dart';
import 'package:sk_works/features/people/company_transfer_send_page.dart';

const actor='00000000-0000-0000-0000-000000000001';
const companyA='00000000-0000-0000-0000-000000000010';
const companyB='00000000-0000-0000-0000-000000000020';
const worker='00000000-0000-0000-0000-000000000030';
PersonnelPrivacySnapshot snapshot({String company=companyA,String role='admin',bool manage=true})=>PersonnelPrivacySnapshot(
 actor:actor,company:company,role:role,canManage:manage,records:[{
 'id':worker,'kind':'employee','name':'Private Worker','address':'Private Address',
 'bloodType':'A','active':true,'familyMembers':[{'id':'family','name':'Private Family','relation':'子'}],
 }]);
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 test('explicit company B owner does not inherit first-company A manager denial',() async{
  final calls=<String>[];
  final client=SupabaseClient('https://personnel-fixture.invalid','fixture-only-key',
   authOptions:const AuthClientOptions(autoRefreshToken:false),httpClient:MockClient((request)async{
    if(request.url.path.endsWith('/company_members')){
     final company=request.url.queryParameters['company_id'];
     return http.Response(jsonEncode(company==null?[{'company_id':companyA,'role':'manager'},{'company_id':companyB,'role':'owner'}]:[{'company_id':company=='eq.$companyB'?companyB:companyA,'role':company=='eq.$companyB'?'owner':'manager'}]),200,request:request,headers:{'content-type':'application/json'});
    }
    if(request.url.path.endsWith('/rpc/employee_personnel_view')){
     final body=jsonDecode(request.body) as Map;calls.add(body['p_company'] as String);
     if(body['p_company']==companyA)return http.Response(jsonEncode({'code':'42501','message':'denied','details':null,'hint':null}),403,request:request,headers:{'content-type':'application/json'});
     return http.Response(jsonEncode({'company_id':companyB,'records':snapshot(company:companyB).records}),200,request:request,headers:{'content-type':'application/json'});
    }
    if(request.url.path.endsWith('/workers'))return http.Response(jsonEncode([{'id':worker,'name':'Private Worker','affiliation':'employee','status':'active'}]),200,request:request,headers:{'content-type':'application/json'});
    if(request.url.path.endsWith('/partner_companies'))return http.Response('[]',200,request:request,headers:{'content-type':'application/json'});
    throw StateError('Unexpected fixture request ${request.url.path}');
   }));
  final repository=PeopleCloudRepository.forTesting(client,actor:()=>actor);
  expect(await repository.canViewPeople(companyId:companyA),false);
  final allowed=await repository.readPersonnel(expectedCompany:companyB);
  expect(allowed.company,companyB);expect(allowed.canManage,true);
  expect(allowed.records.single['address'],'Private Address');
  expect((await repository.loadAll(expectedCompany:companyB)).single['address'],'Private Address');
  expect(calls,[companyA,companyB,companyB]);
  await client.dispose();
 });
 test('viewer canonical active-only records and existing read-only contract preserved',()async{
  final client=SupabaseClient('https://personnel-fixture.invalid','fixture-only-key',
   authOptions:const AuthClientOptions(autoRefreshToken:false),httpClient:MockClient((request)async{
    if(request.url.path.endsWith('/company_members'))return http.Response(jsonEncode([{'company_id':companyA,'role':'viewer'}]),200,request:request,headers:{'content-type':'application/json'});
    if(request.url.path.endsWith('/rpc/employee_personnel_view'))return http.Response(jsonEncode({'company_id':companyA,'records':[
      ...snapshot(role:'viewer',manage:false).records,{'id':'inactive','name':'Inactive','active':false},
    ]}),200,request:request,headers:{'content-type':'application/json'});
    throw StateError('Unexpected fixture request ${request.url.path}');
   }));
  final repository=PeopleCloudRepository.forTesting(client,actor:()=>actor);
  final rows=await repository.loadAll(expectedCompany:companyA);
  expect(rows.map((row)=>row['id']),[worker]);
  expect(rows.single['familyMembers'],isNotEmpty);
  expect(await repository.canManagePeople(companyId:companyA),false);
  expect(await repository.canViewPeople(companyId:companyA),true);
  await client.dispose();
 });
 test('manager OFF keeps RLS-authorized basic worker list without legacy private PII RPC',()async{
  final calls=<String>[];
  final client=SupabaseClient('https://personnel-fixture.invalid','fixture-only-key',
   authOptions:const AuthClientOptions(autoRefreshToken:false),httpClient:MockClient((request)async{
    calls.add(request.url.path);
    if(request.url.path.endsWith('/company_members'))return http.Response(jsonEncode([{'company_id':companyA,'role':'manager'}]),200,request:request,headers:{'content-type':'application/json'});
    if(request.url.path.endsWith('/rpc/people_management_records')||request.url.path.endsWith('/rpc/employee_personnel_view'))return http.Response(jsonEncode({'code':'42501','message':'denied','details':null,'hint':null}),403,request:request,headers:{'content-type':'application/json'});
    if(request.url.path.endsWith('/workers')){expect(request.url.queryParameters['select'],isNot(contains('phone')));return http.Response(jsonEncode([{'id':worker,'name':'Basic Worker','role':'現場担当','affiliation':'employee','status':'active'}]),200,request:request,headers:{'content-type':'application/json'});}
    if(request.url.path.endsWith('/partner_companies'))return http.Response('[]',200,request:request,headers:{'content-type':'application/json'});
    throw StateError('Unexpected fixture request ${request.url.path}');
   }));
  final repository=PeopleCloudRepository.forTesting(client,actor:()=>actor);
  final rows=await repository.loadAll(expectedCompany:companyA);
  expect(rows.single['name'],'Basic Worker');expect(rows.single['address'],'');expect(rows.single['familyMembers'],isEmpty);
  expect(await repository.canViewPeople(companyId:companyA),false);expect(await repository.canManagePeople(companyId:companyA),false);
  expect(calls.any((path)=>path.endsWith('/rpc/employee_personnel_rows')),false);
  await client.dispose();
 });
 test('inactive default-company full profile and family survive existing save payload',()async{
  Map? saved;
  final client=SupabaseClient('https://personnel-fixture.invalid','fixture-only-key',
   authOptions:const AuthClientOptions(autoRefreshToken:false),httpClient:MockClient((request)async{
    http.Response response(Object value)=>http.Response(jsonEncode(value),200,request:request,headers:{'content-type':'application/json'});
    final path=request.url.path;
    if(path.endsWith('/company_members'))return response([{'company_id':companyA,'role':'owner'}]);
    if(path.endsWith('/rpc/employee_personnel_view'))return response({'company_id':companyA,'records':[]});
    if(path.endsWith('/rpc/people_management_records'))return response([{'id':worker,'kind':'employee','name':'Inactive Worker','phone':'retained-phone','active':false}]);
    if(path.endsWith('/workers'))return response([{'id':worker,'employee_number':'retained-number','department':'retained-department','hire_date':'2025-01-01'}]);
    if(path.endsWith('/partner_companies'))return response([]);
    if(path.endsWith('/worker_personnel_profiles')){
      expect(request.url.queryParameters['company_id'],'eq.$companyA');expect(request.url.queryParameters['worker_id'],contains(worker));
      return response([{'worker_id':worker,'address':'Retained Address','blood_type':'A','emergency_name':'Retained Contact','family_composition':'Retained Composition'}]);
    }
    if(path.endsWith('/worker_family_members')){
      expect(request.url.queryParameters['company_id'],'eq.$companyA');expect(request.url.queryParameters['worker_id'],contains(worker));
      return response([{'id':'family','worker_id':worker,'name':'Retained Family','relation':'子','birth_date':'2020-01-01','is_dependent':true}]);
    }
    if(path.endsWith('/rpc/save_worker_personnel_profile')){saved=jsonDecode(request.body) as Map;return response({'requires_approval':false});}
    throw StateError('Unexpected fixture request $path');
   }));
  final repository=PeopleCloudRepository.forTesting(client,actor:()=>actor);
  final full=await repository.readPersonnel(expectedCompany:companyA,includeInactive:true);
  expect(full.records.single['active'],false);expect(full.records.single['address'],'Retained Address');
  await repository.savePersonnelProfile(full.records.single);
  final payload=saved!['p_payload'] as Map;
  expect(payload['address'],'Retained Address');expect(payload['phone'],'retained-phone');
  expect((payload['family_members'] as List).single['name'],'Retained Family');
  expect(payload['employee_number'],'retained-number');await client.dispose();
 });
 testWidgets('edit draft survives normal verification and background cover but not denial',(tester)async{
  var denied=false;
  final session=PersonnelPrivacySession(actor:actor,company:companyA,currentActor:()=>actor,load:()async{
   if(denied)throw const PostgrestException(message:'denied',code:'42501');return snapshot();
  });
  await tester.pumpWidget(MaterialApp(home:PersonnelPrivacyView(session:session,builder:(context,rows)=>
    EmployeePersonnelEditPage(record:PersonRecord.fromJson(rows.single),privacySession:session))));
  await tester.pumpAndSettle();
  final name=find.byType(TextField).first;
  await tester.enterText(name,'Unsaved legitimate draft');
  await session.refresh();await tester.pump();expect(find.text('Unsaved legitimate draft'),findsOneWidget);
  session.didChangeAppLifecycleState(AppLifecycleState.paused);await tester.pump();
  expect(find.text('Unsaved legitimate draft'),findsNothing);
  expect(find.text('Unsaved legitimate draft',skipOffstage:false),findsOneWidget);
  session.didChangeAppLifecycleState(AppLifecycleState.resumed);await tester.pump();
  expect(find.text('Unsaved legitimate draft'),findsOneWidget);
  denied=true;await session.refresh();await tester.pump();
  expect(find.text('Unsaved legitimate draft',skipOffstage:false),findsNothing);
  await tester.pumpWidget(const SizedBox());session.dispose();
 });
 test('delivery default hook preserves existing sequence and payload',()async{
  final calls=<String>[];
  final client=SupabaseClient('https://personnel-fixture.invalid','fixture-only-key',authOptions:const AuthClientOptions(autoRefreshToken:false),httpClient:MockClient((request)async{
    final path=request.url.path;final body=jsonDecode(request.body) as Map;calls.add(path.split('/').last);
    Object value;
    if(path.endsWith('/connected_parent_receive_code')){expect(body['p_parent_company_id'],companyB);value='fixture-code';}
    else if(path.endsWith('/company_document_exchange')){expect(body['p_action'],'send');expect(body['p_data']['request_id'],'fixture-request');value={'id':'delivery'};}
    else if(path.endsWith('/append_employee_personnel_details')){expect(body['p_worker_ids'],[worker]);value={};}
    else {throw StateError('Unexpected fixture request $path');}
    return http.Response(jsonEncode(value),200,request:request,headers:{'content-type':'application/json'});
  }));
  final repository=CompanyDocumentExchangeRepository.forTesting(client);
  expect(await repository.sendConnected(requestId:'fixture-request',targetCompanyId:companyB,items:[{'id':worker,'kind':'worker_personnel'}]),'delivery');
  expect(calls,['connected_parent_receive_code','company_document_exchange','append_employee_personnel_details']);await client.dispose();
 });
 test('delivery rechecks each write and denies PII append after an earlier delivery',()async{
  for(final denyAt in [1,2,3]){
    var checks=0;final calls=<String>[];
    final client=SupabaseClient('https://personnel-fixture.invalid','fixture-only-key',authOptions:const AuthClientOptions(autoRefreshToken:false),httpClient:MockClient((request)async{
      final path=request.url.path.split('/').last;calls.add(path);
      final Object value=path=='connected_parent_receive_code'?'fixture-code':{'id':'delivery'};
      return http.Response(jsonEncode(value),200,request:request,headers:{'content-type':'application/json'});
    }));
    final repository=CompanyDocumentExchangeRepository.forTesting(client);
    final result=repository.sendConnected(requestId:'fixture-request',targetCompanyId:companyB,items:[{'id':worker,'kind':'worker_personnel'}],beforeWrite:()async{
      checks++;if(checks==denyAt)throw const PersonnelScopeChanged();
    });
    await expectLater(result,throwsA(denyAt==3?isA<StateError>().having((e)=>e.toString(),'partial delivery warning',contains('基本データは送信済み')):isA<PersonnelScopeChanged>()));
    expect(checks,denyAt);expect(calls.contains('append_employee_personnel_details'),false);
    expect(calls.length,denyAt-1);await client.dispose();
  }
 });
 testWidgets('late shared source response is discarded after people permission denial',(tester)async{
  final source=Completer<http.Response>();var denied=false,checks=0;
  final client=SupabaseClient('https://personnel-fixture.invalid','fixture-only-key',authOptions:const AuthClientOptions(autoRefreshToken:false),httpClient:MockClient((request)async{
    if(request.url.path.endsWith('/company_document_exchange'))return source.future;
    return http.Response('[]',200,request:request,headers:{'content-type':'application/json'});
  }));
  await tester.pumpWidget(MaterialApp(home:CompanyTransferSendPage(title:'Fixture',sourceKind:'worker_personnel',subjectLabel:'社員',workerIds:{worker},description:'Fixture',
    repository:CompanyDocumentExchangeRepository.forTesting(client),beforeLoad:()async{checks++;if(denied)throw const PersonnelScopeChanged();})));
  await tester.pump();denied=true;
  source.complete(http.Response(jsonEncode([{'id':worker,'worker_id':worker,'kind':'worker_personnel','name':'Late Private Name'}]),200,request:http.Request('POST',Uri.parse('https://personnel-fixture.invalid/rest/v1/rpc/company_document_exchange')),headers:{'content-type':'application/json'}));
  await tester.pumpAndSettle();expect(checks,2);expect(find.text('Late Private Name'),findsNothing);
  await tester.pumpWidget(const SizedBox());await client.dispose();
 });
 testWidgets('initial paused lifecycle does not fetch until resumed',(tester)async{
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  var loads=0;
  final session=PersonnelPrivacySession(actor:actor,company:companyA,currentActor:()=>actor,load:()async{loads++;return snapshot();});
  session.start();await tester.pump();expect(loads,0);expect(session.snapshot,isNull);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pump();expect(loads,1);expect(session.snapshot,isNotNull);session.dispose();
 });
 test('permission denial clears old PII and cancels prior output lease',()async{
  var denied=false;
  final session=PersonnelPrivacySession(actor:actor,company:companyA,currentActor:()=>actor,load:()async{
   if(denied)throw const PostgrestException(message:'denied',code:'42501');return snapshot();
  });
  await session.read();final lease=session.epoch;denied=true;await session.refresh();
  expect(session.snapshot,isNull);expect(()=>session.verify(lease),throwsA(isA<PersonnelScopeChanged>()));session.dispose();
 });
 test('background and A-B-A revocation reject a delayed response',()async{
  final pending=Completer<PersonnelPrivacySnapshot>();var current=actor;
  final session=PersonnelPrivacySession(actor:actor,company:companyA,currentActor:()=>current,load:()=>pending.future);
  final read=session.read();session.didChangeAppLifecycleState(AppLifecycleState.paused);
  current='other';session.revoke();current=actor;pending.complete(snapshot());
  await expectLater(read,throwsA(isA<PersonnelScopeChanged>()));expect(session.snapshot,isNull);session.dispose();
 });
 test('same actor company change cannot replace old route with other company data',()async{
  final session=PersonnelPrivacySession(actor:actor,company:companyA,currentActor:()=>actor,load:()async=>snapshot(company:companyB));
  await expectLater(session.read(),throwsA(isA<PersonnelScopeChanged>()));expect(session.revoked,true);expect(session.snapshot,isNull);session.dispose();
 });
 testWidgets('open detail removes address and family on permission cancellation',(tester)async{
  var denied=false;
  final session=PersonnelPrivacySession(actor:actor,company:companyA,currentActor:()=>actor,load:()async{
   if(denied)throw const PostgrestException(message:'denied',code:'42501');return snapshot();
  });
  await tester.pumpWidget(MaterialApp(home:EmployeePersonnelDetailPage(
   record:const PersonRecord(id:worker,kind:PersonKind.employee,name:''),allEmployees:const[],
   companyName:'Fixture',canViewFamily:true,privacySession:session)));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.text('Private Address'),300,scrollable:find.byType(Scrollable).first);
  expect(find.text('Private Address'),findsWidgets);
  denied=true;await session.refresh();await tester.pump();
  expect(find.text('Private Address'),findsNothing);expect(find.text('Private Family'),findsNothing);
  await tester.pumpWidget(const SizedBox());session.dispose();
 });
 testWidgets('send action fresh-read failure never invokes send callback',(tester)async{
  var denied=false,sent=0;
  final session=PersonnelPrivacySession(actor:actor,company:companyA,currentActor:()=>actor,load:()async{
   if(denied)throw const PostgrestException(message:'denied',code:'42501');return snapshot();
  });
  await tester.pumpWidget(MaterialApp(home:EmployeePersonnelPrintPage(companyName:'Fixture',
   records:const[PersonRecord(id:worker,kind:PersonKind.employee,name:'')],
   privacySession:session,action:EmployeePersonnelPreviewAction.send,onConfirmSend:(_)async{sent++;})));
  await tester.pumpAndSettle();denied=true;
  await tester.tap(find.byIcon(Icons.send_outlined));await tester.pumpAndSettle();
  expect(sent,0);expect(find.text('Private Address'),findsNothing);
  await tester.pumpWidget(const SizedBox());session.dispose();
 });
}
