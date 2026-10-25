import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/attendance/gps_work_schedule_selection_flow.dart';
import 'package:sk_works/features/attendance/scheduled_checkout_repository.dart';
const actor='00000000-0000-0000-0000-000000000010';
const company='00000000-0000-0000-0000-000000000001';
const worker='00000000-0000-0000-0000-000000000020';
const site='00000000-0000-0000-0000-000000000030';
const nextSite='00000000-0000-0000-0000-000000000031';
GpsWorkScheduleConfiguration cfg({String id=worker,String destination=site})=>GpsWorkScheduleConfiguration(
 companyId:company,workerId:id,siteId:destination,weekdays:const [1,3,5],clockInTime:'22:00:00',checkoutTime:'06:00:00',
 checkoutNextDay:true,revision:7,enabled:true,timezone:'Asia/Tokyo');
class Repo extends ScheduledCheckoutRepository{
 Repo(List<GpsWorkScheduleConfiguration> configurations):_configurations=configurations,
  super(SupabaseClient('https://synthetic.invalid','fixture-only',authOptions:const AuthClientOptions(autoRefreshToken:false)));
 final List<GpsWorkScheduleConfiguration> _configurations;
 String identity='same-actor-session';bool switchSession=false;
 @override String? get currentSessionIdentity=>identity;
 @override String? get actorId=>actor;
 @override Future<ScheduledCheckoutNotificationPlan> loadNotificationPlan()async{
  if(switchSession)identity='another-session';
  return ScheduledCheckoutNotificationPlan(actorId:actor,configurations:_configurations,
   state:ScheduledCheckoutState(actorId:actor,enabled:true,serverTime:DateTime.utc(2026,10,25),targets:const []),plannedNotifications:const []);
 }
}
void main(){
 test('changing destination preserves both registered times and the revision CAS',()async{
  final repo=Repo([cfg()]);addTearDown(repo.client.dispose);
  final loaded=await GpsWorkScheduleSelection.load(repository:repo,siteId:nextSite);
  expect(loaded.expectedRevision,7);expect(loaded.draft.clockInDatabase,'22:00:00');
  expect(loaded.draft.checkoutDatabase,'06:00:00');expect(loaded.draft.checkoutNextDay,isTrue);expect(loaded.draft.weekdays,[1,3,5]);
 });
 test('legacy GPS configuration gets visible fallback input, not a fake saved revision',()async{
  final repo=Repo([]);addTearDown(repo.client.dispose);
  final loaded=await GpsWorkScheduleSelection.load(repository:repo,siteId:site,
   fallbackWeekdays:const [2,4],fallbackClockIn:const TimeOfDay(hour:9,minute:30));
  expect(loaded.expectedRevision,0);expect(loaded.draft.clockInDatabase,'09:30:00');expect(loaded.draft.checkoutDatabase,'17:00:00');
 });
 test('ambiguous company configuration does not silently choose the first worker',()async{
  final repo=Repo([cfg(),cfg(id:'00000000-0000-0000-0000-000000000021',destination:'00000000-0000-0000-0000-000000000032')]);addTearDown(repo.client.dispose);
  await expectLater(GpsWorkScheduleSelection.load(repository:repo,siteId:nextSite),throwsStateError);
 });
 test('session switch while configuration loads discards the result',()async{
  final repo=Repo([cfg()])..switchSession=true;addTearDown(repo.client.dispose);
  await expectLater(GpsWorkScheduleSelection.load(repository:repo,siteId:site),throwsStateError);
 });
 testWidgets('editing the popup preserves saved revision and both values',(tester)async{
  final repo=Repo([cfg()]);addTearDown(repo.client.dispose);
  final loaded=await GpsWorkScheduleSelection.load(repository:repo,siteId:site);
  GpsWorkScheduleSelection? edited;
  await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(
   onPressed:()async{edited=await loaded.choose(context);},child:const Text('edit'))))));
  await tester.tap(find.text('edit'));await tester.pumpAndSettle();expect(find.text('06:00（翌日）'),findsOneWidget);
  await tester.tap(find.text('保存'));await tester.pumpAndSettle();expect(edited?.expectedRevision,7);expect(edited?.draft.checkoutDatabase,'06:00:00');
 });
 testWidgets('missing destination fails before requesting any device permission',(tester)async{
  final repo=Repo([cfg()]);addTearDown(repo.client.dispose);
  final loaded=await GpsWorkScheduleSelection.load(repository:repo,siteId:site);
  late BuildContext context;
  await tester.pumpWidget(MaterialApp(home:Builder(builder:(c){context=c;return const Scaffold();})));
  await expectLater(loaded.save(context),throwsStateError);
 });
}
