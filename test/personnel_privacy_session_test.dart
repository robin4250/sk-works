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
     return http.Response(jsonEncode(company==null?[{'company_id':companyA,'role':'manager'},{'company_id':companyB,'role':'owner'}]:[{'company_id':company=='eq.$companyB'?companyB:companyA,'role':company=='eq.$companyB'?'owner':'manager'}]),200);
    }
    if(request.url.path.endsWith('/rpc/employee_personnel_view')){
     final body=jsonDecode(request.body) as Map;calls.add(body['p_company'] as String);
     if(body['p_company']==companyA)return http.Response(jsonEncode({'code':'42501','message':'denied','details':null,'hint':null}),403);
     return http.Response(jsonEncode({'company_id':companyB,'records':snapshot(company:companyB).records}),200);
    }
    if(request.url.path.endsWith('/workers'))return http.Response(jsonEncode([{'id':worker,'name':'Private Worker','affiliation':'employee','status':'active'}]),200);
    if(request.url.path.endsWith('/partner_companies'))return http.Response('[]',200);
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
    if(request.url.path.endsWith('/company_members'))return http.Response(jsonEncode([{'company_id':companyA,'role':'viewer'}]),200);
    if(request.url.path.endsWith('/rpc/employee_personnel_view'))return http.Response(jsonEncode({'company_id':companyA,'records':[
      ...snapshot(role:'viewer',manage:false).records,{'id':'inactive','name':'Inactive','active':false},
    ]}),200);
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
    if(request.url.path.endsWith('/company_members'))return http.Response(jsonEncode([{'company_id':companyA,'role':'manager'}]),200);
    if(request.url.path.endsWith('/rpc/people_management_records')||request.url.path.endsWith('/rpc/employee_personnel_view'))return http.Response(jsonEncode({'code':'42501','message':'denied','details':null,'hint':null}),403);
    if(request.url.path.endsWith('/workers')){expect(request.url.queryParameters['select'],isNot(contains('phone')));return http.Response(jsonEncode([{'id':worker,'name':'Basic Worker','role':'現場担当','affiliation':'employee','status':'active'}]),200);}
    if(request.url.path.endsWith('/partner_companies'))return http.Response('[]',200);
    throw StateError('Unexpected fixture request ${request.url.path}');
   }));
  final repository=PeopleCloudRepository.forTesting(client,actor:()=>actor);
  final rows=await repository.loadAll(expectedCompany:companyA);
  expect(rows.single['name'],'Basic Worker');expect(rows.single['address'],'');expect(rows.single['familyMembers'],isEmpty);
  expect(await repository.canViewPeople(companyId:companyA),false);expect(await repository.canManagePeople(companyId:companyA),false);
  expect(calls.any((path)=>path.endsWith('/rpc/employee_personnel_rows')),false);
  await client.dispose();
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
  await tester.pumpAndSettle();expect(find.text('Private Address'),findsWidgets);
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
