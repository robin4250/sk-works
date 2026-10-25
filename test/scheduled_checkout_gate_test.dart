import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/scheduled_checkout_gate.dart';
import 'package:sk_works/features/attendance/scheduled_checkout_repository.dart';
const actor='00000000-0000-0000-0000-000000000010';
ScheduledCheckoutState state({bool due=true,bool manage=false,bool off=false})=>ScheduledCheckoutState(
 actorId:actor,enabled:!off,serverTime:DateTime.utc(2026,10,25,8),targets:off?[]:[ScheduledCheckoutTarget(
 companyId:'00000000-0000-0000-0000-000000000001',workerId:'00000000-0000-0000-0000-000000000020',
 sourceId:'00000000-0000-0000-0000-000000000040',siteId:'00000000-0000-0000-0000-000000000030',
 workDate:'2026-10-25',reminderAt:DateTime.utc(2026,10,25,due?7:9),due:due,scopeFingerprint:'v1',canManageAttendance:manage)]);
void main(){
 testWidgets('due confirmation hides ordinary page and never clocks out by timer',(tester)async{
  var loads=0,checkouts=0;
  await tester.pumpWidget(MaterialApp(home:ScheduledCheckoutGate(actorId:actor,
   load:()async{loads++;return state();},postpone:(_)async=>state(due:false),
   checkoutBuilder:(_,t){checkouts++;return const Text('real checkout');},child:const Scaffold(body:Text('ordinary')))));
  await tester.pumpAndSettle();expect(find.text('退勤予定時刻です。'),findsOneWidget);expect(find.text('ordinary'),findsNothing);
  expect(await ScheduledCheckoutGateController.instance.handleSystemBack(),isTrue);expect(checkouts,0);expect(loads,1);
  await tester.pumpWidget(const SizedBox());
 });
 testWidgets('still working unlocks only after persisted server postponement',(tester)async{
  ScheduledCheckoutTarget? submitted;
  await tester.pumpWidget(MaterialApp(home:ScheduledCheckoutGate(actorId:actor,load:()async=>state(),
   postpone:(target)async{submitted=target;return state(due:false);},checkoutBuilder:(_,t)=>const Text('real checkout'),
   child:const Scaffold(body:Text('ordinary')))));
  await tester.pumpAndSettle();await tester.tap(find.text('まだ勤務中・30分後に再通知'));await tester.pumpAndSettle();
  expect(submitted?.scopeFingerprint,'v1');expect(find.text('ordinary'),findsOneWidget);
  expect(await ScheduledCheckoutGateController.instance.handleSystemBack(),isFalse);
  await tester.pumpWidget(const SizedBox());
 });
 testWidgets('returning from checkout without server clockout remains restricted',(tester)async{
  await tester.pumpWidget(MaterialApp(home:ScheduledCheckoutGate(actorId:actor,load:()async=>state(),
   postpone:(_)async=>state(due:false),checkoutBuilder:(context,t)=>Scaffold(body:TextButton(
    onPressed:()=>Navigator.pop(context),child:const Text('return without save'))),child:const Scaffold(body:Text('ordinary')))));
  await tester.pumpAndSettle();await tester.tap(find.text('退勤して日報へ'));await tester.pumpAndSettle();
  await tester.tap(find.text('return without save'));await tester.pumpAndSettle();
  expect(find.text('ordinary'),findsNothing);expect(find.text('退勤予定時刻です。'),findsOneWidget);
  await tester.pumpWidget(const SizedBox());
 });
 testWidgets('scoped management is visible only with server feature permission',(tester)async{
  Widget host(bool manage)=>MaterialApp(home:ScheduledCheckoutGate(key:ValueKey(manage),actorId:actor,
   load:()async=>state(manage:manage),postpone:(_)async=>state(due:false),checkoutBuilder:(_,t)=>const Text('real checkout'),
   managementBuilder:(_,t)=>const Scaffold(body:Text('authorized management')),child:const Scaffold(body:Text('ordinary'))));
  await tester.pumpWidget(host(false));await tester.pumpAndSettle();expect(find.text('管理者の勤怠管理で確認'),findsNothing);
  await tester.pumpWidget(host(true));await tester.pumpAndSettle();await tester.tap(find.text('管理者の勤怠管理で確認'));await tester.pumpAndSettle();
  expect(find.text('authorized management'),findsOneWidget);expect(find.text('ordinary'),findsNothing);
  expect(await ScheduledCheckoutGateController.instance.handleSystemBack(),isTrue);await tester.pumpAndSettle();
  expect(find.text('退勤予定時刻です。'),findsOneWidget);await tester.pumpWidget(const SizedBox());
 });
 testWidgets('API failure is not treated as no outstanding checkout',(tester)async{
  await tester.pumpWidget(MaterialApp(home:ScheduledCheckoutGate(actorId:actor,load:()async=>throw StateError('offline'),
   postpone:(_)async=>state(),checkoutBuilder:(_,t)=>const Text('real checkout'),child:const Scaffold(body:Text('ordinary')))));
  await tester.pumpAndSettle();expect(find.text('ordinary'),findsNothing);expect(find.text('もう一度確認'),findsOneWidget);
  expect(await ScheduledCheckoutGateController.instance.handleSystemBack(),isTrue);await tester.pumpWidget(const SizedBox());
 });
 testWidgets('OFF response allows ordinary app while retaining active capability distinction',(tester)async{
  await tester.pumpWidget(MaterialApp(home:ScheduledCheckoutGate(actorId:actor,load:()async=>state(off:true),
   postpone:(_)async=>state(),checkoutBuilder:(_,t)=>const Text('real checkout'),child:const Scaffold(body:Text('ordinary')))));
  await tester.pumpAndSettle();expect(find.text('ordinary'),findsOneWidget);await tester.pumpWidget(const SizedBox());
 });
}
