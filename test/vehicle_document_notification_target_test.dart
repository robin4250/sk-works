import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/operations/vehicle_route_page.dart';
import 'package:sk_works/features/operations/vehicle_route_repository.dart';
import 'package:sk_works/features/notifications/notifications_page.dart';
import 'package:sk_works/features/notifications/app_notification_repository.dart';

const target = '12345678-1234-1234-1234-123456789abc';
const other = '87654321-4321-4321-4321-cba987654321';
class FakeVehicleRepository extends VehicleRouteRepository {
  FakeVehicleRepository() : super.forTesting(SupabaseClient('https://fixture.invalid','fixture-key', authOptions: const AuthClientOptions(autoRefreshToken: false)));
  String? actor = 'actor-a';
  bool allowed = true;
  List<Map<String,dynamic>> rows = [{'id':other,'display_name':'別車両'},{'id':target,'display_name':'通知対象車両'}];
  Completer<List<Map<String,dynamic>>>? pending;
  Object? failure;
  @override String? get selectionActorId => actor;
  @override Future<List<Map<String,dynamic>>> vehicles({bool activeOnly=false}) async {
    if (failure != null) throw failure!;
    return pending == null ? rows : pending!.future;
  }
  @override Future<Map<String,dynamic>> permissions() async => {'can_manage_vehicles':allowed};
}
Future<void> show(WidgetTester tester,FakeVehicleRepository repo,{
 String id=target,Stream<String?>? actors,void Function(Map<String,dynamic>)? opened,
}) async {
 await tester.pumpWidget(MaterialApp(home: VehicleRoutePage(
   initialVehicleId:id,repository:repo,actorChanges:actors,
   notificationEditorBuilder:(row){opened?.call(row);return Scaffold(
     appBar:AppBar(title:const Text('書類編集')),
     body:Text('編集車両:${row['id']}'));},
 )));
 await tester.pumpAndSettle();
}
void main(){
 test('vehicle notification passes its saved ID; missing ID does not open generic list',(){
  AppNotificationRecord notice(String? id)=>AppNotificationRecord(id:'notice',kind:'warning',title:'書類',body:'',
    createdAt:DateTime(2026),read:false,actionKey:'vehicle_documents',actionId:id);
  expect((notificationDestination(notice(target)) as VehicleRoutePage).initialVehicleId,target);
  expect((notificationDestination(notice(null)) as VehicleRoutePage).initialVehicleId,'');
 });
 testWidgets('opens only exact RLS-loaded vehicle once despite rebuild and return',(tester) async{
  final repo=FakeVehicleRepository();var count=0;
  await show(tester,repo,opened:(row){count++;expect(row['id'],target);});
  expect(find.text('編集車両:$target'),findsOneWidget);expect(count,1);
  await tester.pump();expect(count,1);
  await tester.pageBack();await tester.pumpAndSettle();
  expect(find.text('通知対象車両'),findsOneWidget);expect(find.text('別車両'),findsNothing);
  await tester.pump();expect(count,1);
 });
 testWidgets('missing exact vehicle explains why without another vehicle fallback',(tester) async{
  final repo=FakeVehicleRepository()..rows=[{'id':other,'display_name':'別車両'}];var count=0;
  await show(tester,repo,opened:(_)=>count++);
  expect(find.textContaining('通知の車両が見つかりません'),findsOneWidget);
  expect(find.text('別車両'),findsNothing);expect(count,0);
 });
 testWidgets('permission denial never opens editor',(tester) async{
  final repo=FakeVehicleRepository()..allowed=false;var count=0;
  await show(tester,repo,opened:(_)=>count++);
  expect(find.textContaining('編集する権限がありません'),findsOneWidget);expect(count,0);
 });
 testWidgets('invalid identifier and transport failure retain explicit target error',(tester) async{
  var count=0;final repo=FakeVehicleRepository();
  await show(tester,repo,id:'bad',opened:(_)=>count++);
  expect(find.textContaining('車両IDが無効'),findsOneWidget);expect(count,0);
  await tester.pumpWidget(const SizedBox.shrink());
  repo.failure=StateError('通信失敗');
  await show(tester,repo,opened:(_)=>count++);
  expect(find.textContaining('通信失敗'),findsOneWidget);expect(count,0);
 });
 testWidgets('account change discards delayed vehicle response',(tester) async{
  final repo=FakeVehicleRepository()..pending=Completer<List<Map<String,dynamic>>>();
  final actors=StreamController<String?>.broadcast();var count=0;
  await tester.pumpWidget(MaterialApp(home:VehicleRoutePage(initialVehicleId:target,
   repository:repo,actorChanges:actors.stream,notificationEditorBuilder:(_){count++;return const Text('unsafe');})));
  await tester.pump();repo.actor='actor-b';actors.add('actor-b');await tester.pump();
  repo.pending!.complete(repo.rows);await tester.pumpAndSettle();
  expect(count,0);expect(find.textContaining('ログイン情報が変更'),findsOneWidget);
  await tester.pumpWidget(const SizedBox.shrink());await actors.close();
 });
 testWidgets('open editor hides on actor change and stays invalid after switching back',(tester) async{
  final repo=FakeVehicleRepository();final actors=StreamController<String?>.broadcast();
  await show(tester,repo,actors:actors.stream);
  repo.actor='actor-b';actors.add('actor-b');await tester.pumpAndSettle();
  expect(find.text('編集車両:$target'),findsNothing);
  expect(find.textContaining('ログイン情報が変更'),findsWidgets);
  repo.actor='actor-a';actors.add('actor-a');await tester.pumpAndSettle();
  expect(find.text('編集車両:$target'),findsNothing);
  await tester.pumpWidget(const SizedBox.shrink());await actors.close();
 });
}
