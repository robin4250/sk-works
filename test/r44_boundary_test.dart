// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:convert';
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
http.Response jsonResponse(Object body,http.Request request)=>http.Response(jsonEncode(body),200,request:request,headers:{'content-type':'application/json'});
String token()=>['{"alg":"HS256"}',jsonEncode({'sub':actor,'role':'authenticated','exp':DateTime.now().millisecondsSinceEpoch~/1000+3600}),'signature'].map((x)=>base64Url.encode(utf8.encode(x)).replaceAll('=','')).join('.');

class Fixture {
  final rows=Completer<void>();
  final signed=Completer<void>();
  final rowStarted=Completer<void>();
  final signStarted=Completer<void>();
  late final SupabaseClient client=SupabaseClient('https://certificate-fixture.invalid','fixture-key',authOptions:const AuthClientOptions(autoRefreshToken:false),httpClient:MockClient((request) async {
    final path=request.url.path;
    if(path.endsWith('/token'))return jsonResponse({'access_token':token(),'refresh_token':'fixture-refresh','token_type':'bearer','expires_in':3600,'user':{'id':actor,'aud':'authenticated','role':'authenticated','email':'fixture@example.invalid','created_at':'2026-01-01T00:00:00Z','app_metadata':{},'user_metadata':{}}},request);
    if(path.endsWith('/logout'))return http.Response('',204,request:request);
    if(path.endsWith('/rpc/current_feature_permissions'))return jsonResponse({'can_manage_people':true},request);
    if(path.endsWith('/company_members'))return jsonResponse([{'company_id':company}],request);
    if(path.endsWith('/qualification_master'))return jsonResponse([{'id':'master','name':'Private qualification'}],request);
    if(path.endsWith('/workers'))return jsonResponse([{'id':worker,'name':'Private worker'}],request);
    if(path.endsWith('/worker_qualifications')){
      if(!rowStarted.isCompleted)rowStarted.complete();
      await rows.future;
      return jsonResponse([{'id':'qualification','worker_id':worker,'qualification_master_id':'master','certificate_number':'PRIVATE-CERT','attachment_path':'$company/$worker/front.jpg'}],request);
    }
    if(path.contains('/object/sign/')){
      if(!signStarted.isCompleted)signStarted.complete();
      await signed.future;
      return jsonResponse({'signedURL':'/object/sign/qualification-certificates/private.jpg?token=synthetic-only'},request);
    }
    throw StateError('Unexpected synthetic request: $path');
  }));
  Future<void> login()=>client.auth.signInWithPassword(email:'fixture@example.invalid',password:'synthetic-only').then((_){});
  Future<void> close()async{if(!rows.isCompleted)rows.complete();if(!signed.isCompleted)signed.complete();await client.dispose();}
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
  });
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
  });
}
