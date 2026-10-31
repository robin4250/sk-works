import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/people/people_page.dart';
import 'package:sk_works/features/people/people_cloud_repository.dart';
import 'package:sk_works/features/people/employee_personnel_edit_page.dart';
import 'package:sk_works/features/people/employee_personnel_detail_page.dart';
import 'package:sk_works/features/people/worker_personnel_change_approvals_page.dart';
import 'app_auth_mutation_gateway_test.dart' as fixture;
const company='60000000-0000-0000-0000-000000000010';
const worker='60000000-0000-0000-0000-000000000020';
void main(){
 test('birthday model serializes worker date independently of family dates',(){
  final record=PersonRecord.fromJson({'id':worker,'birth_date':'1980-02-29','birth_date_contract_version':2,
   'familyMembers':[{'name':'Child','relation':'子','birth_date':'2020-01-01'}]});
  expect(record.birthDate,'1980-02-29');expect(record.birthDateContractVersion,2);
  expect(PersonRecord.fromJson(Map<String,dynamic>.from(record.toJson())).birthDate,'1980-02-29');
  expect(record.familyMembers.single.birthDate?.year,2020);
 });
 test('date validation rejects invalid, future and out-of-range worker birthdays',(){
  for(final value in ['1980-02-31','2999-01-01','1899-12-31','2020-1-1']){
   expect(()=>PeopleCloudRepository.validatePersonnelMetadata({'birthDateSubmitted':true,'birthDate':value}),throwsStateError);
  }
  for(final value in ['1980-02-29','']){
   PeopleCloudRepository.validatePersonnelMetadata({'birthDateSubmitted':true,'birthDate':value});
  }
 });
 testWidgets('older database contract shows birthday input as preparation pending',(t)async{
  await t.pumpWidget(const MaterialApp(home:EmployeePersonnelEditPage(record:PersonRecord(id:worker,kind:PersonKind.employee,name:'Fixture'))));
  expect(find.text('生年月日'),findsOneWidget);
  expect(find.text('生年月日の登録は準備中です'),findsOneWidget);
  final tile=t.widget<ListTile>(find.ancestor(of:find.text('生年月日'),matching:find.byType(ListTile)).first);
  expect(tile.onTap,isNull);
  await t.pumpWidget(const SizedBox.shrink());
 });
 testWidgets('detail displays worker birthday in personal data table',(t)async{
  await t.pumpWidget(const MaterialApp(home:EmployeePersonnelDetailPage(
   record:PersonRecord(id:worker,kind:PersonKind.employee,name:'Fixture',birthDate:'1980-02-29'),
   allEmployees:[],companyName:'Fixture',canManage:false,canViewFamily:false)));
  expect(find.text('生年月日'),findsOneWidget);expect(find.text('1980/02/29'),findsOneWidget);
  await t.pumpWidget(const SizedBox.shrink());
 });
 testWidgets('approval review labels worker birthday and hides contract marker',(t)async{
  await t.pumpWidget(MaterialApp(home:WorkerPersonnelChangeApprovalsPage(loadRequests:()async=>[
   {'id':'request-fixture','worker_name':'Fixture','proposed':{'name':'Fixture',
    'birth_date':'1980-02-29','birth_date_contract_version':2}}
  ])));
  await t.pumpAndSettle();
  await t.tap(find.byType(ExpansionTile));await t.pumpAndSettle();
  expect(find.text('生年月日'),findsOneWidget);expect(find.text('1980-02-29'),findsOneWidget);
  expect(find.textContaining('birth_date_contract_version'),findsNothing);
  await t.pumpWidget(const SizedBox.shrink());
 });
 for(final supported in [false,true]) { test('fresh server contract $supported controls canonical birthday submission',()async{
  final w=fixture.Wire();await w.seed();addTearDown(w.client.dispose);
  Map<String,dynamic>? saved;
  w.respond=(r)async{
   if(r.url.path.endsWith('/company_members'))return fixture.Wire.json([{'company_id':company,'role':'admin'}]);
   if(r.url.path.endsWith('/rpc/employee_personnel_view')) {
    return fixture.Wire.json({'company_id':company,if(supported)'birth_date_contract_version':2,
     'records':[{'id':worker,'active':true,if(supported)'birthDateContractVersion':2,if(supported)'personnelCasDigest':'0123456789abcdef0123456789abcdef'}]});
   }
   if(r.url.path.endsWith('/rpc/save_worker_personnel_profile')){
    saved=jsonDecode(r.body) as Map<String,dynamic>;
    return fixture.Wire.json({'status':'pending','requires_approval':true});
   }
   throw StateError('Unexpected fixture endpoint');
  };
  final future=PeopleCloudRepository.forClient(w.client).savePersonnelProfile({
   'id':worker,'name':'Fixture','birthDateSubmitted':true,'birthDate':'1980-02-29',
   'birthDateContractVersion':2,'birthDateExpected':null,'personnelCasDigest':'0123456789abcdef0123456789abcdef','birthDateOnly':true},expectedCompany:company);
  if(!supported){await expectLater(future,throwsStateError);expect(saved,isNull);}
  else{final result=await future;expect(result['requires_approval'],true);
   expect((saved!['p_payload'] as Map)['birth_date'],'1980-02-29');
   expect((saved!['p_payload'] as Map).containsKey('family_members'),false);
   expect(((saved!['p_payload'] as Map)['_birth_date_cas'] as Map)['expected_birth_date'],null);
   expect(((saved!['p_payload'] as Map)['_birth_date_cas'] as Map)['version'],2);
   expect(w.calls.last.headers['Authorization'],'Bearer ${w.client.auth.currentSession!.accessToken}');}
 }); }
 test('legacy omitted date does not add or clear birthday in canonical payload',()async{
  final w=fixture.Wire();addTearDown(w.client.dispose);Map? saved;
  w.respond=(r)async{saved=jsonDecode(r.body) as Map;return fixture.Wire.json({'status':'saved'});};
  await PeopleCloudRepository.forClient(w.client).savePersonnelProfile({'id':worker,'name':'Fixture'});
  expect((saved!['p_payload'] as Map).containsKey('birth_date'),false);
 });
}

