import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/chat/chat_cloud_repository.dart';
class _RealHttp extends HttpOverrides {}
void main() {
 TestWidgetsFlutterBinding.ensureInitialized();
 for(final mode in ['target','changed','unavailable','creation_changed']) {
  test('LINE confirmation company scope: $mode',()=>HttpOverrides.runWithHttpOverrides(() async {
   const actor='11111111-1111-4111-8111-111111111111';
   const companyA='22222222-2222-4222-8222-222222222222';
   const companyB='33333333-3333-4333-8333-333333333333';
   var groupReads=0,membershipReads=0;
   final server=await HttpServer.bind(InternetAddress.loopbackIPv4,0);
   server.listen((request) async {
    Object data;
    if(request.uri.path=='/auth/v1/token') {
     String encode(Object value)=>base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=','');
     data={'access_token':'${encode({'alg':'HS256'})}.${encode({'sub':actor,'exp':DateTime.now().millisecondsSinceEpoch~/1000+3600})}.fixture','refresh_token':'fixture','token_type':'bearer','expires_in':3600,'user':{'id':actor,'aud':'authenticated','role':'authenticated','email':'a@example.test','app_metadata':{},'user_metadata':{},'created_at':'2026-01-01T00:00:00Z'}};
    } else if(request.uri.path.endsWith('/communication_groups')) {
     expect(request.uri.queryParameters['id'],'eq.target');groupReads++;
     data=[{'company_id':mode=='changed' && groupReads>1 ? companyA : companyB}];
    } else if(request.uri.path.endsWith('/companies')) {
     expect(request.uri.queryParameters['id'],'eq.$companyB');
     data=mode=='unavailable'?[]:[{'name':'Actual target company B'}];
    } else if(request.uri.path.endsWith('/company_members')) {
     membershipReads++;data=[{'company_id':companyB,'role':'owner'}];
    } else { throw StateError('unexpected endpoint'); }
    request.response.headers.contentType=ContentType.json;request.response.write(jsonEncode(data));await request.response.close();
   });
   final client=SupabaseClient('http://127.0.0.1:${server.port}','fixture',authOptions:const AuthClientOptions(autoRefreshToken:false));
   try {
    await client.auth.signInWithPassword(email:'a@example.test',password:'fixture');
    final repository=ChatCloudRepository.forTesting(client);
    if(mode=='creation_changed') {
     await expectLater(repository.lineLinkCompanyName(creationCompanyId:companyA),throwsStateError);expect(groupReads,0);
    } else if(mode=='changed') {
     await expectLater(repository.lineLinkCompanyName(groupId:'target'),throwsStateError);expect(membershipReads,0);
    } else {
     expect(await repository.lineLinkCompanyName(groupId:'target'),mode=='unavailable'?null:'Actual target company B');
     expect(membershipReads,0);expect(groupReads,2);
    }
   } finally {await client.dispose();await server.close(force:true);}
  },_RealHttp()));
 }
}
