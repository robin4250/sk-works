import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/people/people_cloud_page.dart';
import 'package:sk_works/features/people/people_cloud_repository.dart';
import 'package:sk_works/features/people/partner_company_bank_page.dart';

const actor='00000000-0000-0000-0000-000000000001';
const company='00000000-0000-0000-0000-000000000002';
const firstPartner='00000000-0000-0000-0000-000000000003';
const selectedPartner='00000000-0000-0000-0000-000000000004';
List<Map<String,dynamic>> roster({String selectedName='Selected partner',bool includeSelected=true})=>[
 {'id':firstPartner,'name':'First partner','kind':'partnerCompany','active':true},
 if(includeSelected){'id':selectedPartner,'name':selectedName,'kind':'partnerCompany','active':true},
];
class FakePeople implements PeopleCloudRepository {
 String? currentActor=actor;
 String role='admin';bool manage=true;
 late PersonnelPrivacySession session;
 int rosterReads=0;
 Completer<List<Map<String,dynamic>>>? delayedRoster;
 List<Map<String,dynamic>> freshRows=roster();
 @override String? get actorId=>currentActor;
 PersonnelPrivacySnapshot snapshot()=>PersonnelPrivacySnapshot(actor:actor,company:company,
  role:role,canManage:manage,records:const[]);
 @override Future<({String companyId,String role})> membership({String? companyId})async=>
  (companyId:company,role:role);
 @override PersonnelPrivacySession privacySession(String company){
  session=PersonnelPrivacySession(actor:actor,company:company,currentActor:()=>currentActor,
   load:()async=>snapshot());return session;
 }
 @override Future<List<Map<String,dynamic>>> loadAll({String? expectedCompany})async{
  expect(expectedCompany,company);rosterReads++;
  if(rosterReads==1)return roster();
  final pending=delayedRoster;
  if(pending!=null)return await pending.future;
  return freshRows;
 }
 @override Future<bool> canManagePeople({String? companyId})async=>manage;
 @override Future<bool> canViewPeople({String? companyId})async=>true;
 @override Future<bool> canConfigurePersonnelApprovers({String? companyId})async=>false;
 @override Future<String> companyName({String? companyId})async=>'Display company';
 @override dynamic noSuchMethod(Invocation invocation)=>super.noSuchMethod(invocation);
}
Future<void> openSelectedSheet(WidgetTester t,FakePeople repo)async{
 await t.pumpWidget(MaterialApp(home:PeopleCloudPage(companyId:company,repositoryOverride:repo)));
 await t.pumpAndSettle();
 await t.tap(find.widgetWithText(ChoiceChip,'協力会社'));await t.pumpAndSettle();
 await t.tap(find.text('Selected partner'));await t.pumpAndSettle();
}
void main(){
 testWidgets('selected partner bank opens root route with fresh fixed scope after sheet closes',(t)async{
  final repo=FakePeople();repo.freshRows=roster(selectedName:'Fresh selected partner');
  await openSelectedSheet(t,repo);
  await t.tap(find.byKey(const Key('partner-company-bank-entry')));await t.pumpAndSettle();
  final page=t.widget<PartnerCompanyBankPage>(find.byType(PartnerCompanyBankPage));
  expect(identical(page.privacySession,repo.session),true);
  expect(page.expectedCompany,company);expect(page.partnerCompanyId,selectedPartner);
  expect(page.partnerName,'Fresh selected partner');expect(find.byType(BottomSheet),findsNothing);
  expect(repo.rosterReads,2);
  await t.pumpWidget(const SizedBox.shrink());
 });
 testWidgets('read-only personnel role has no partner bank action',(t)async{
  final repo=FakePeople();repo.manage=false;repo.role='viewer';
  await openSelectedSheet(t,repo);
  expect(find.byKey(const Key('partner-company-bank-entry')),findsNothing);
  expect(find.byType(PartnerCompanyBankPage),findsNothing);
  await t.pumpWidget(const SizedBox.shrink());
 });
 testWidgets('removed selected partner cannot fall back to first roster company',(t)async{
  final repo=FakePeople();repo.freshRows=roster(includeSelected:false);
  await openSelectedSheet(t,repo);
  await t.tap(find.byKey(const Key('partner-company-bank-entry')));await t.pumpAndSettle();
  expect(find.byType(PartnerCompanyBankPage),findsNothing);
  await t.pumpWidget(const SizedBox.shrink());
 });
 for(final invalidation in ['permission','background','actor']){
  testWidgets('$invalidation change during fresh roster read prevents opening bank route',(t)async{
   final repo=FakePeople();repo.delayedRoster=Completer<List<Map<String,dynamic>>>();
   await openSelectedSheet(t,repo);
   await t.tap(find.byKey(const Key('partner-company-bank-entry')));await t.pump();await t.pump();
   expect(repo.rosterReads,2);
   if(invalidation=='permission'){
    repo.manage=false;repo.role='viewer';await repo.session.refresh();
   }else if(invalidation=='background'){
    repo.session.didChangeAppLifecycleState(AppLifecycleState.paused);
   }else{
    repo.currentActor=null;repo.session.revoke();
   }
   repo.delayedRoster!.complete(roster());await t.pumpAndSettle();
   expect(find.byType(PartnerCompanyBankPage),findsNothing);
   await t.pumpWidget(const SizedBox.shrink());
  });
 }
}
