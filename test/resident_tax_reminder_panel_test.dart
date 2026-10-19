import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/payroll/resident_tax_reminder_repository.dart';
import 'package:sk_works/features/payroll/resident_tax_reminder_panel.dart';
const company='00000000-0000-0000-0000-000000000100';
const other='00000000-0000-0000-0000-000000000200';
class FakeReminder implements ResidentTaxReminderRepository{
 String? actor='actor';final changes=StreamController<String?>.broadcast(sync:true);bool edit=true,missing=false;int saves=0;
 final pending=<String,Completer<ResidentTaxReminderSettings>>{};Completer<ResidentTaxReminderSettings>? savePending;
 @override String? get actorId=>actor;
 @override Stream<String?> get actorChanges=>changes.stream;
 ResidentTaxReminderSettings value(String cid,{bool enabled=false})=>ResidentTaxReminderSettings(companyId:cid,enabled:enabled,canEdit:edit,updatedAt:null);
 @override Future<ResidentTaxReminderSettings> read(String cid)async{if(missing)throw const PostgrestException(message:'missing',code:'PGRST202');return pending[cid]?.future??Future.value(value(cid));}
 @override Future<ResidentTaxReminderSettings> save(ResidentTaxReminderSettings expected,bool enabled)async{saves++;return savePending?.future??Future.value(value(expected.companyId,enabled:enabled));}
 @override Future<ResidentTaxReminderTarget> target(String n,String c,{bool requireWorkspace=true})async=>throw UnimplementedError();
}
void main(){
 Future<void> show(WidgetTester tester,FakeReminder fake,{String cid=company})async{
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:SingleChildScrollView(child:ResidentTaxReminderPanel(key:const ValueKey('panel'),companyId:cid,repository:fake)))));
  await tester.pumpAndSettle();
 }
 Future<void> expand(WidgetTester tester)async{await tester.tap(find.text('住民税の切替通知（会社共通）'));await tester.pumpAndSettle();}
 testWidgets('missing backend is OFF preparation and does not block another save',(tester)async{
  final fake=FakeReminder()..missing=true;addTearDown(fake.changes.close);await show(tester,fake);await expand(tester);
  expect(find.textContaining('通知はOFFのまま'),findsOneWidget);expect(find.byType(SwitchListTile),findsNothing);expect(fake.saves,0);
 });
 testWidgets('viewer reads but cannot toggle',(tester)async{
  final fake=FakeReminder()..edit=false;addTearDown(fake.changes.close);await show(tester,fake);await expand(tester);
  expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,isNull);
 });
 testWidgets('duplicate save disabled while pending',(tester)async{
  final fake=FakeReminder()..savePending=Completer();addTearDown(fake.changes.close);await show(tester,fake);await expand(tester);
  await tester.tap(find.byType(Switch));await tester.pump();expect(fake.saves,1);
  expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,isNull);
  fake.savePending!.complete(fake.value(company,enabled:true));await tester.pumpAndSettle();expect(fake.saves,1);
 });
 testWidgets('company ABA ignores stale first load',(tester)async{
  final fake=FakeReminder();addTearDown(fake.changes.close);final first=Completer<ResidentTaxReminderSettings>();fake.pending[company]=first;
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:SingleChildScrollView(child:ResidentTaxReminderPanel(key:const ValueKey('panel'),companyId:company,repository:fake)))));await tester.pump();
  fake.pending.remove(company);await show(tester,fake,cid:other);await show(tester,fake);first.complete(fake.value(company,enabled:true));await tester.pumpAndSettle();await expand(tester);
  expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,false);
 });
 testWidgets('actor change is rejected before the stream notification arrives',(tester)async{
  final fake=FakeReminder();addTearDown(fake.changes.close);await show(tester,fake);await expand(tester);
  fake.actor='different';await tester.tap(find.byType(Switch));await tester.pumpAndSettle();
  expect(fake.saves,0);expect(find.textContaining('画面を開き直してください'),findsOneWidget);
 });
 testWidgets('logout same actor ABA permanently closes old panel',(tester)async{
  final fake=FakeReminder();addTearDown(fake.changes.close);await show(tester,fake);await expand(tester);
  fake.actor=null;fake.changes.add(null);fake.actor='actor';fake.changes.add('actor');await tester.pumpAndSettle();
  expect(find.textContaining('画面を開き直してください'),findsOneWidget);expect(find.byType(SwitchListTile),findsNothing);
 });
}
