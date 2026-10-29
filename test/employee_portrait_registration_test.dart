import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/people/employee_portrait_repository.dart';
import 'package:sk_works/features/people/employee_portrait_registration_page.dart';
import 'package:sk_works/features/people/people_cloud_repository.dart';
import 'package:sk_works/features/people/worker_document_repository.dart';
import 'package:sk_works/features/people/worker_document_photos.dart';
import 'worker_document_managed_save_http_test.dart' as managed;

class _NativeFixtureHttp extends HttpOverrides {}

class _Documents extends WorkerDocumentRepository {
 _Documents(this.fixture):super.forTesting(fixture.client);
 final managed.Fixture fixture;
 bool missing=false,inactive=false,foreign=false;
 @override Future<Map<String,List<Map<String,dynamic>>>> loadAll({bool includeHiddenRequirements=false}) async=>{
  'workers':[if(!inactive){'id':managed.worker,'status':'active'}],
  'requirements':[if(!missing){'id':managed.requirement,'company_id':foreign?'foreign':managed.company,'name':'顔写真','scope':'internal','is_active':true,'sort_order':0}],
  'statuses':[if((fixture.saved??fixture.existing) case final row?) {...row,'worker_id':managed.worker,'requirement_id':managed.requirement}],
 };
}
Future<void> drainPortraitIo(WidgetTester tester) async {
 final clock=Stopwatch()..start();
 while(find.byType(LinearProgressIndicator).evaluate().isNotEmpty){
  if(clock.elapsed>const Duration(seconds:5)){throw StateError('portrait fixture IO did not settle');}
  await tester.runAsync(() async {await Future<void>.delayed(const Duration(milliseconds:5));});
  await tester.pump(Duration.zero);
 }
 await tester.pumpAndSettle();
}
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 late managed.Fixture f;late PersonnelPrivacySession session;late _Documents docs;late EmployeePortraitRepository repo;
 setUp(() async {
  f=managed.Fixture();
  await HttpOverrides.runZoned(f.start,createHttpClient:(context)=>_NativeFixtureHttp().createHttpClient(context));docs=_Documents(f);
  session=PersonnelPrivacySession(actor:managed.actor,company:managed.company,currentActor:()=>f.client.auth.currentUser?.id,
    load:() async=>PersonnelPrivacySnapshot(actor:managed.actor,company:managed.company,role:f.role,canManage:f.role!='viewer',records:[{'id':managed.worker}]));
  repo=EmployeePortraitRepository.forTesting(privacySession:session,workerId:managed.worker,client:f.client,documents:docs);
 });
 tearDown(() async {await repo.dispose();session.dispose();await f.close();});
 WorkerDocumentPhoto photo()=>WorkerDocumentPhoto.pending(base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='),'portrait.png');
 test('actual managed HTTP upload then row binding retains originals and resets new-photo verification',() async {
  f.existing={'id':managed.statusId,'updated_at':'2026-10-11T00:00:00Z','attachment_path':managed.savedPath,'attachment_paths':[managed.savedPath],'status':'verified','original_verified':true,'notes':'keep'};
  final draft=await repo.load();await repo.save(draft,photo());
  expect(f.saved!['worker_id'],managed.worker);expect(f.saved!['requirement_id'],managed.requirement);
  expect(f.saved!['status'],'submitted');expect(f.saved!['original_verified'],false);expect(f.saved!['notes'],'keep');
  expect((f.saved!['attachment_paths'] as List).last,managed.savedPath);
  expect(f.requests.where((r)=>r.method=='DELETE'),isEmpty);
  final patch=f.requests.singleWhere((r)=>r.method=='PATCH');
  expect(patch.uri.queryParameters['updated_at'],'eq.2026-10-11T00:00:00Z');
 });
 for(final scenario in ['missing','inactive','foreign','viewer','storage denied','stale']){
  test('$scenario refuses without deleting originals or reporting success',() async {
   if(scenario=='missing'){docs.missing=true;}
   if(scenario=='inactive'){docs.inactive=true;}
   if(scenario=='foreign'){docs.foreign=true;}
   if(scenario=='viewer'){f.role='viewer';}
   if(scenario=='storage denied'){f.uploadDenied=true;}
   if(['missing','inactive','foreign','viewer'].contains(scenario)){
    await expectLater(repo.load(),throwsA(anything));expect(f.mutations,isEmpty);return;
   }
   final draft=await repo.load();
   if(scenario=='stale')f.existing={'id':managed.statusId,'updated_at':'2026-10-20T00:00:00Z'};
   await expectLater(repo.save(draft,photo()),throwsA(anything));expect(f.saved,isNull);
   expect(f.requests.where((r)=>r.method=='DELETE'),isEmpty);
   if(scenario=='storage denied'){expect(f.requests.where((r)=>r.uri.path.endsWith('/worker_document_statuses')&&r.method!='GET'),isEmpty);}
  });
 }
 test('Auth switch during actual upload prevents metadata write via additive scope hook',() async {
  final draft=await repo.load();f.switchActor=true;
  await expectLater(repo.save(draft,photo()),throwsA(anything));expect(f.saved,isNull);
  expect(f.requests.where((r)=>r.uri.path.endsWith('/worker_document_statuses')&&r.method!='GET'),isEmpty);
 });
 test('fresh same-UID sign-in invalidates captured portrait owner before any upload',() async {
  final draft=await repo.load();
  await f.client.auth.signInWithPassword(email:'fixture@example.test',password:'fixture');
  await Future<void>.delayed(Duration.zero);
  expect(f.client.auth.currentUser?.id,managed.actor);
  await expectLater(repo.save(draft,photo()),throwsA(anything));expect(f.mutations,isEmpty);
 });
 test('additive scope callback refuses metadata after upload even when UID is unchanged',() async {
  var refused=false;
  await expectLater(WorkerDocumentRepository.forTesting(f.client).saveManagedDocumentPhotos(
    workerId:managed.worker,requirementId:managed.requirement,status:'submitted',originalVerified:false,notes:'',photos:[photo()],expectedRow:null,
    requireScope:(){if(f.requests.any((r)=>r.uri.path.startsWith('/storage/v1/object/'))){refused=true;throw const PersonnelScopeChanged();}}),throwsA(anything));
  expect(refused,true);expect(f.client.auth.currentUser?.id,managed.actor);expect(f.saved,isNull);
 });
 test('invalid PDF, empty and oversized input cannot call Storage',() async {
  final draft=await repo.load();
  for(final input in [WorkerDocumentPhoto.pending(Uint8List.fromList(utf8.encode('%PDF-1.7')),'photo.pdf'),WorkerDocumentPhoto.pending(Uint8List(0),'empty.jpg'),WorkerDocumentPhoto.pending(Uint8List(6*1024*1024+1),'large.jpg')]){
   await expectLater(repo.save(draft,input),throwsA(anything));
  }
  expect(f.mutations,isEmpty);
 });
 testWidgets('photo page requires explicit selection/save; cancellation never uploads',(tester) async {
  await tester.pumpWidget(MaterialApp(home:EmployeePortraitRegistrationPage(privacySession:session,workerId:managed.worker,companyName:'テスト会社',repositoryOverride:repo,photoPicker:(_)async=>[photo()])));
  await drainPortraitIo(tester);
  final save=find.byKey(const Key('employee-portrait-save'));expect(tester.widget<FilledButton>(save).onPressed,isNull);
  await tester.tap(find.byKey(const Key('employee-portrait-pick')));await tester.pump();await drainPortraitIo(tester);
  expect(tester.widget<FilledButton>(save).onPressed,isNotNull);expect(f.mutations,isEmpty);
  await tester.tap(find.text('キャンセル'));await tester.pumpAndSettle();expect(f.mutations,isEmpty);
  await tester.pumpWidget(const SizedBox());
 });
 testWidgets('missing face requirement offers existing explicit settings entry without creating rows',(tester) async {
  docs.missing=true;
  await tester.pumpWidget(MaterialApp(home:EmployeePortraitRegistrationPage(privacySession:session,workerId:managed.worker,companyName:'テスト会社',repositoryOverride:repo)));
  await drainPortraitIo(tester);
  expect(find.byKey(const Key('employee-portrait-settings')),findsOneWidget);expect(f.mutations,isEmpty);
  await tester.pumpWidget(const SizedBox());
 });
}
