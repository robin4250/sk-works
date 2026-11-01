// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/qualifications/qualification_certificate_page.dart';
import 'package:sk_works/features/qualifications/qualification_certificate_repository.dart';

const actor='00000000-0000-0000-0000-000000000001';
const worker='00000000-0000-0000-0000-000000000002';
const company='00000000-0000-0000-0000-000000000003';
const master='00000000-0000-0000-0000-000000000005';
const qualification='00000000-0000-0000-0000-000000000006';
http.Response jsonResponse(Object body,http.Request request)=>http.Response(jsonEncode(body),200,request:request,headers:{'content-type':'application/json'});
String token([String userId=actor])=>['{"alg":"HS256"}',jsonEncode({'sub':userId,'session_id':'00000000-0000-0000-0000-000000000007','role':'authenticated','exp':DateTime.now().millisecondsSinceEpoch~/1000+3600}),'signature'].map((x)=>base64Url.encode(utf8.encode(x)).replaceAll('=','')).join('.');

class Fixture {
  String activeActor=actor;
  bool waitForPermission=false;
  bool waitForStorage=false;
  final storageStarted=Completer<void>();
  final storageComplete=Completer<void>();
  final permission=Completer<void>();
  final permissionStarted=Completer<void>();
  final mutations=<String>[];
  final calls=<String>[];
  final requestMethods=<String>[];
  final rows=Completer<void>();
  final signed=Completer<void>();
  final rowStarted=Completer<void>();
  final signStarted=Completer<void>();
  late final SupabaseClient client=SupabaseClient('https://certificate-fixture.invalid','fixture-key',authOptions:const AuthClientOptions(autoRefreshToken:false),httpClient:MockClient((request) async {
    final path=request.url.path;calls.add(path);requestMethods.add(request.method);
    if(path.endsWith('/token'))return jsonResponse({'access_token':token(activeActor),'refresh_token':'fixture-refresh','token_type':'bearer','expires_in':3600,'user':{'id':activeActor,'aud':'authenticated','role':'authenticated','email':'fixture@example.invalid','created_at':'2026-01-01T00:00:00Z','app_metadata':{},'user_metadata':{}}},request);
    if(path.endsWith('/logout'))return http.Response('',204,request:request);
    if(path.endsWith('/rpc/current_feature_permissions')){
      if(!permissionStarted.isCompleted)permissionStarted.complete();
      if(waitForPermission)await permission.future;
      return jsonResponse({'can_manage_people':true},request);
    }
    if(path.endsWith('/company_members'))return jsonResponse([{'company_id':company,'role':'admin'}],request);
    if(path.endsWith('/qualification_master'))return jsonResponse([{'id':master,'company_id':company,'name':'Private qualification'}],request);
    if(path.endsWith('/workers'))return jsonResponse([{'id':worker,'company_id':company,'status':'active','name':'Private worker'}],request);
    if(path.endsWith('/worker_qualifications') && request.method=='PATCH'){
      mutations.add('database');return jsonResponse({'id':'qualification','worker_id':worker,...(jsonDecode(request.body) as Map<String,dynamic>)},request);
    }
    if(path.contains('/storage/v1/object/') && !path.contains('/object/sign/')){
      mutations.add('storage');
      if(!storageStarted.isCompleted)storageStarted.complete();
      if(waitForStorage)await storageComplete.future;
      return jsonResponse({'Key':'qualification-certificates/synthetic-only.jpg'},request);
    }
    if(path.endsWith('/worker_qualifications')){
      if(!rowStarted.isCompleted)rowStarted.complete();
      await rows.future;
      return jsonResponse([{'id':qualification,'company_id':company,'worker_id':worker,'qualification_master_id':master,'certificate_number':'PRIVATE-CERT','attachment_path':'$company/$worker/front.jpg'}],request);
    }
    if(path.contains('/object/sign/')){
      if(!signStarted.isCompleted)signStarted.complete();
      await signed.future;
      return jsonResponse({'signedURL':'/object/sign/qualification-certificates/private.jpg?token=synthetic-only'},request);
    }
    throw StateError('Unexpected synthetic request: $path');
  }));
  Future<void> login()=>client.auth.signInWithPassword(email:'fixture@example.invalid',password:'synthetic-only').then((_){});
  Future<void> close()async{if(!storageComplete.isCompleted)storageComplete.complete();if(!permission.isCompleted)permission.complete();if(!rows.isCompleted)rows.complete();if(!signed.isCompleted)signed.complete();await client.dispose();}
}

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('late qualification rows cannot reappear after SDK logout',(tester)async{
    final f=Fixture();addTearDown(f.close);await tester.runAsync(f.login);
    await tester.pumpWidget(MaterialApp(home:QualificationCertificatePage(repository:QualificationCertificateRepository.forTesting(f.client))));
    await tester.pump();await tester.pump();expect(f.rowStarted.isCompleted,true);
    await tester.runAsync(()=>f.client.auth.signOut(scope:SignOutScope.local));
    expect(f.client.auth.currentUser,isNull);await tester.pump();
    f.rows.complete();await tester.pump();await tester.pump();
    expect(find.text('Private qualification'),findsNothing);
    expect(find.textContaining('PRIVATE-CERT'),findsNothing);
  }, timeout: const Timeout(Duration(seconds: 45)));
  testWidgets('late signed URL and open photo sheet disappear after SDK logout',(tester)async{
    final f=Fixture();addTearDown(f.close);await tester.runAsync(f.login);f.rows.complete();
    await tester.pumpWidget(MaterialApp(home:QualificationCertificatePage(repository:QualificationCertificateRepository.forTesting(f.client))));
    await tester.pump();await tester.pump();await tester.pump();
    expect(find.text('Private qualification'),findsOneWidget);
    await tester.tap(find.text('Private qualification'));await tester.pump();await tester.pump(const Duration(milliseconds:400));
    expect(f.signStarted.isCompleted,true);
    await tester.runAsync(()=>f.client.auth.signOut(scope:SignOutScope.local));
    expect(f.client.auth.currentUser,isNull);await tester.pump();
    f.signed.complete();await tester.pump();await tester.pump();
    expect(find.byType(Image),findsNothing);
    expect(find.textContaining('PRIVATE-CERT'),findsNothing);
  }, timeout: const Timeout(Duration(seconds: 45)));
  testWidgets('already displayed photo is removed and retained list callback cannot reopen after logout',(tester)async{
    final f=Fixture();addTearDown(f.close);await tester.runAsync(f.login);f.rows.complete();f.signed.complete();
    await tester.pumpWidget(MaterialApp(home:QualificationCertificatePage(repository:QualificationCertificateRepository.forTesting(f.client))));
    await tester.pump();await tester.pump();await tester.pump();
    final tile=tester.widget<ListTile>(find.ancestor(of:find.text('Private qualification'),matching:find.byType(ListTile)).first);
    final retained=tile.onTap;expect(retained,isNotNull);
    await tester.tap(find.text('Private qualification'));await tester.pump();await tester.pump(const Duration(milliseconds:400));await tester.pump();
    for (var i=0;i<30 && find.byType(Image).evaluate().isEmpty;i++) {
      await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:5)));
      await tester.pump(const Duration(milliseconds:10));
    }
    expect(f.signStarted.isCompleted,true);
    expect(find.byType(Image),findsOneWidget);
    // Saved-photo edit callbacks are removed while approval requests are unavailable.
    expect(find.text('撮り直す'),findsNothing);
    expect(f.mutations,isEmpty);
    await tester.runAsync(()=>f.client.auth.signOut(scope:SignOutScope.local));await tester.pump();
    expect(find.byType(Image),findsNothing);expect(find.textContaining('PRIVATE-CERT'),findsNothing);
    final before=f.calls.length;retained!();await tester.pump();
    expect(f.calls.length,before);expect(tester.takeException(),isNull);
  },timeout:const Timeout(Duration(seconds:45)));

  testWidgets('same actor new session discards the old read and a fresh route can reload',(tester)async{
    final f=Fixture();addTearDown(f.close);await tester.runAsync(f.login);
    await tester.pumpWidget(MaterialApp(home:QualificationCertificatePage(repository:QualificationCertificateRepository.forTesting(f.client))));
    await tester.pump();await tester.pump();expect(f.rowStarted.isCompleted,true);
    await tester.runAsync(f.login);await tester.pump();f.rows.complete();await tester.pump();await tester.pump();
    expect(find.text('Private qualification'),findsNothing);
    await tester.pumpWidget(MaterialApp(home:QualificationCertificatePage(key:const ValueKey('reauth-fresh'),repository:QualificationCertificateRepository.forTesting(f.client))));
    await tester.pump();await tester.pump();
    expect(find.text('Private qualification'),findsOneWidget);
  },timeout:const Timeout(Duration(seconds:45)));

  test('signed URL result is refused after actual SDK logout',()async{
    final f=Fixture();addTearDown(f.close);await f.login();
    final repository=QualificationCertificateRepository.forTesting(f.client);f.rows.complete();
    final future=repository.createSignedUrl('$company/$worker/front.jpg');
    await f.signStarted.future;final checked=expectLater(future,throwsStateError);
    await f.client.auth.signOut(scope:SignOutScope.local);f.signed.complete();await checked;
  });

  testWidgets('actor replacement discards delayed qualification rows',(tester)async{
    final f=Fixture();addTearDown(f.close);await tester.runAsync(f.login);
    await tester.pumpWidget(MaterialApp(home:QualificationCertificatePage(repository:QualificationCertificateRepository.forTesting(f.client))));
    await tester.pump();await tester.pump();expect(f.rowStarted.isCompleted,true);
    f.activeActor='00000000-0000-0000-0000-000000000004';
    await tester.runAsync(f.login);await tester.pump();f.rows.complete();await tester.pump();await tester.pump();
    expect(f.client.auth.currentUser?.id,f.activeActor);
    expect(find.text('Private qualification'),findsNothing);
  },timeout:const Timeout(Duration(seconds:45)));

  test('logout and same-actor return does not revive an old pending URL',()async{
    final f=Fixture();addTearDown(f.close);await f.login();
    f.rows.complete();
    final future=QualificationCertificateRepository.forTesting(f.client).createSignedUrl('$company/$worker/front.jpg');
    await f.signStarted.future;final checked=expectLater(future,throwsStateError);
    await f.client.auth.signOut(scope:SignOutScope.local);await f.login();
    f.signed.complete();await checked;
    final fresh=await QualificationCertificateRepository.forTesting(f.client).createSignedUrl('$company/$worker/front.jpg');
    expect(fresh,contains('synthetic-only'));
  });

  testWidgets('a fresh route works after same-actor logout and relogin',(tester)async{
    final f=Fixture();addTearDown(f.close);await tester.runAsync(f.login);f.rows.complete();
    final repository=QualificationCertificateRepository.forTesting(f.client);
    await tester.pumpWidget(MaterialApp(home:QualificationCertificatePage(key:const ValueKey('old'),repository:repository)));
    await tester.pump();await tester.pump();expect(find.text('Private qualification'),findsOneWidget);
    await tester.runAsync(()=>f.client.auth.signOut(scope:SignOutScope.local));await tester.pump();
    await tester.runAsync(f.login);await tester.pump();expect(find.text('Private qualification'),findsNothing);
    await tester.pumpWidget(MaterialApp(home:QualificationCertificatePage(key:const ValueKey('fresh'),repository:repository)));
    await tester.pump();await tester.pump();expect(find.text('Private qualification'),findsOneWidget);
  },timeout:const Timeout(Duration(seconds:45)));

  test('permission response after actor replacement cannot dispatch old upload',()async{
    final f=Fixture();addTearDown(f.close);await f.login();f.rows.complete();f.waitForPermission=true;
    Object? failure;
    final pending=QualificationCertificateRepository.forTesting(f.client).uploadCertificate(qualificationId:'qualification',workerId:worker,bytes:Uint8List.fromList([1,2]),originalFilename:'synthetic.jpg').catchError((Object error){failure=error;return <String,dynamic>{};});
    await f.permissionStarted.future;
    f.activeActor='00000000-0000-0000-0000-000000000004';await f.login();
    f.permission.complete();await pending;
    expect(f.mutations,isEmpty);expect(failure,isStateError);
  });
  test('logout and same actor return cannot resume an old removal permission check',()async{
    final f=Fixture();addTearDown(f.close);await f.login();f.rows.complete();f.waitForPermission=true;
    Object? failure;
    final pending=QualificationCertificateRepository.forTesting(f.client).removeCertificate(qualificationId:'qualification',storagePath:'synthetic.jpg').catchError((Object error){failure=error;return <String,dynamic>{};});
    await f.permissionStarted.future;
    await f.client.auth.signOut(scope:SignOutScope.local);await f.login();f.permission.complete();await pending;
    expect(f.mutations,isEmpty);expect(failure,isStateError);
  });
  test('legitimate active actor upload dispatches once and updates once',()async{
    final f=Fixture();addTearDown(f.close);await f.login();f.rows.complete();
    await QualificationCertificateRepository.forTesting(f.client).uploadCertificate(qualificationId:'qualification',workerId:worker,bytes:Uint8List.fromList([1,2]),originalFilename:'synthetic.jpg');
    expect(f.mutations,['storage','database']);
  });

  test('permission response after logout cannot dispatch a removal',()async{
    final f=Fixture();addTearDown(f.close);await f.login();f.waitForPermission=true;
    final pending=QualificationCertificateRepository.forTesting(f.client).removeCertificate(qualificationId:'qualification',storagePath:'synthetic.jpg');
    await f.permissionStarted.future;final checked=expectLater(pending,throwsStateError);
    await f.client.auth.signOut(scope:SignOutScope.local);f.permission.complete();await checked;
    expect(f.mutations,isEmpty);
  });
  test('same actor token refresh preserves a pending legitimate upload',()async{
    final f=Fixture();addTearDown(f.close);await f.login();f.rows.complete();f.waitForPermission=true;
    final pending=QualificationCertificateRepository.forTesting(f.client).uploadCertificate(qualificationId:'qualification',workerId:worker,bytes:Uint8List.fromList([1,2]),originalFilename:'synthetic.jpg');
    await f.permissionStarted.future;await f.client.auth.refreshSession();f.permission.complete();await pending;
    expect(f.mutations,['storage','database']);
  });
  test('logout after Storage dispatch suppresses later DB update without cleanup',()async{
    final f=Fixture();addTearDown(f.close);await f.login();f.rows.complete();f.waitForStorage=true;
    final pending=QualificationCertificateRepository.forTesting(f.client).uploadCertificate(qualificationId:'qualification',workerId:worker,bytes:Uint8List.fromList([1,2]),originalFilename:'synthetic.jpg');
    await f.storageStarted.future;final checked=expectLater(pending,throwsStateError);
    await f.client.auth.signOut(scope:SignOutScope.local);await f.login();f.storageComplete.complete();await checked;
    expect(f.mutations,['storage']);
    expect(f.requestMethods.where((method)=>method=='DELETE'),isEmpty);
  });

}
