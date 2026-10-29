import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/people/employee_bank_account_section.dart';
import 'package:sk_works/features/people/employee_personnel_detail_page.dart';
import 'package:sk_works/features/people/people_cloud_repository.dart';
import 'package:sk_works/features/people/people_page.dart';

const actor='00000000-0000-0000-0000-000000000001';
const company='00000000-0000-0000-0000-000000000002';
const worker='00000000-0000-0000-0000-000000000003';
PersonnelPrivacySnapshot snapshot() => const PersonnelPrivacySnapshot(
 actor:actor,company:company,role:'admin',canManage:true,
 records:[{'id':worker,'kind':'employee','name':'Selected employee','active':true}]);
PersonnelPrivacySession privacy() {
 final value=PersonnelPrivacySession(actor:actor,company:company,currentActor:()=>actor,
  load:()async=>snapshot());
 value.snapshot=snapshot();return value;
}
void main(){
 testWidgets('employee bank entry binds selected worker and privacy company',(t)async{
  final session=privacy();
  await t.pumpWidget(MaterialApp(home:EmployeePersonnelDetailPage(
   record:const PersonRecord(id:worker,kind:PersonKind.employee,name:'Untrusted shell'),
   allEmployees:const[],companyName:'Display label only',canViewFamily:true,privacySession:session)));
  await t.pump();
  final entry=t.widget<EmployeeBankAccountSection>(find.byType(EmployeeBankAccountSection));
  expect(entry.companyId,company);expect(entry.workerId,worker);expect(entry.employeeName,'Selected employee');
  expect(entry.key,const ValueKey('employee-bank:$company:$worker'));
  await t.pumpWidget(const SizedBox.shrink());session.dispose();
 });
 testWidgets('local sample without privacy session has no bank registration entry',(t)async{
  await t.pumpWidget(const MaterialApp(home:EmployeePersonnelDetailPage(
   record:PersonRecord(id:worker,kind:PersonKind.employee,name:'Sample'),
   allEmployees:[],companyName:'Sample',canViewFamily:false)));
  expect(find.byType(EmployeeBankAccountSection),findsNothing);
  await t.pumpWidget(const SizedBox.shrink());
 });
 for (final saved in [true, false]) {
  testWidgets('portrait reload follows confirmed selected employee save $saved',(t)async{
   final session=privacy();var loads=0;final seen=<String>[];
   await t.pumpWidget(MaterialApp(home:EmployeePersonnelDetailPage(
    record:const PersonRecord(id:worker,kind:PersonKind.employee,name:'Shell'),
    allEmployees:const[],companyName:'Display company',canViewFamily:true,privacySession:session,
    portraitLoader:()async{loads++;return null;},
    portraitRegistrationBuilder:(bound,id,label){
     expect(identical(bound,session),true);seen.add(id);expect(label,'Display company');
     return Scaffold(body:Builder(builder:(context)=>TextButton(
      onPressed:()=>Navigator.of(context).pop(saved),child:const Text('fixture result'))));
    })));
   await t.pumpAndSettle();expect(loads,1);
   await t.tap(find.byKey(const Key('employee-portrait-register')));await t.pumpAndSettle();
   expect(seen,everyElement(worker));expect(seen,isNotEmpty);
   await t.tap(find.text('fixture result'));await t.pumpAndSettle();
   expect(loads,saved?2:1);
   await t.pumpWidget(const SizedBox.shrink());session.dispose();
  });
 }
 testWidgets('portrait save result after privacy revocation cannot reload the old employee',(t)async{
  final session=privacy();var loads=0;
  await t.pumpWidget(MaterialApp(home:EmployeePersonnelDetailPage(
   record:const PersonRecord(id:worker,kind:PersonKind.employee,name:'Shell'),
   allEmployees:const[],companyName:'Display company',canViewFamily:true,privacySession:session,
   portraitLoader:()async{loads++;return null;},
   portraitRegistrationBuilder:(_,_,_)=>Scaffold(body:Builder(builder:(context)=>TextButton(
    onPressed:(){session.revoke();Navigator.of(context).pop(true);},child:const Text('revoke then result')))))));
  await t.pumpAndSettle();expect(loads,1);
  await t.tap(find.byKey(const Key('employee-portrait-register')));await t.pumpAndSettle();
  await t.tap(find.text('revoke then result'));await t.pumpAndSettle();
  expect(loads,1);
  await t.pumpWidget(const SizedBox.shrink());session.dispose();
 });

}
