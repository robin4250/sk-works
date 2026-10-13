import 'dart:convert';import 'dart:io';
import 'package:flutter_test/flutter_test.dart';import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/features/chat/chat_cloud_repository.dart';
class _RealHttp extends HttpOverrides {}
void main(){TestWidgetsFlutterBinding.ensureInitialized();
 test('summaries paginate beyond 100, exclude self and blocked sender, and preserve source body/time',()=>HttpOverrides.runWithHttpOverrides(()async{
 const actor='11111111-1111-4111-8111-111111111111';var pages=0;
 final server=await HttpServer.bind(InternetAddress.loopbackIPv4,0);
 server.listen((request)async{Object data;
 if(request.uri.path=='/auth/v1/token'){
 String encode(Object v)=>base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=','');
 data={'access_token':'${encode({'alg':'HS256'})}.${encode({'sub':actor,'exp':DateTime.now().millisecondsSinceEpoch~/1000+3600})}.fixture','refresh_token':'fixture','token_type':'bearer','expires_in':3600,'user':{'id':actor,'aud':'authenticated','role':'authenticated','email':'a@example.test','app_metadata':{},'user_metadata':{},'created_at':'2026-01-01T00:00:00Z'}};
 }else if(request.uri.path.endsWith('/chat_block_list')){data=[{'user_id':'blocked'}];
 }else if(request.uri.queryParameters['limit']=='1'){data=[{'id':'last','body':'実際の最新本文','sent_at':'2026-10-13T01:00:00Z','sender_user_id':'other'}];
 }else{pages++;final offset=int.parse(request.uri.queryParameters['offset']??'0');
 data=offset==0?List.generate(1000,(i)=>{'id':'$i','sender_user_id':i==0?actor:i==1?'blocked':'other','sent_at':'2026-10-13T00:00:00Z'}):[{'id':'1000','sender_user_id':'other','sent_at':'2026-10-13T01:00:00Z'}];}
 request.response.headers.contentType=ContentType.json;request.response.write(jsonEncode(data));await request.response.close();});
 final client=SupabaseClient('http://127.0.0.1:${server.port}','fixture',authOptions:const AuthClientOptions(autoRefreshToken:false));
 try{await client.auth.signInWithPassword(email:'a@example.test',password:'fixture');
 final result=await ChatCloudRepository.forTesting(client).loadConversationSummaries({'g':DateTime.utc(2026,10,12)});
 expect(result['g']!.unread,999);expect(pages,2);expect(result['g']!.body,'実際の最新本文');expect(result['g']!.sentAt,'2026-10-13T01:00:00Z');
 }finally{await client.dispose();await server.close(force:true);}
 },_RealHttp()));}
