import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/notifications/notifications_page.dart';
import 'package:sk_works/features/notifications/notification_explanation_page.dart';
import 'package:sk_works/features/notifications/attention_center_item.dart';
const actor='11111111-1111-4111-8111-111111111111';
const target='22222222-2222-4222-8222-222222222222';
String session(String sid){
 String part(Object x)=>base64Url.encode(utf8.encode(jsonEncode(x))).replaceAll('=','');
 return jsonEncode({'access_token':'${part({'alg':'HS256'})}.${part({'sub':actor,'role':'authenticated','session_id':sid,'exp':4102444800})}.synthetic','refresh_token':'synthetic','token_type':'bearer','expires_in':3600,'user':{'id':actor,'aud':'authenticated','created_at':'2026-01-01T00:00:00Z','app_metadata':{},'user_metadata':{}}});
}
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 for(final mode in ['missing','forbidden','present']){
  test('read-only SDK report availability $mode',()async{
   var reads=0;
   final client=SupabaseClient('https://synthetic.invalid','synthetic',authOptions:const AuthClientOptions(autoRefreshToken:false),httpClient:MockClient((r)async{
    reads++;expect(r.method,'GET');expect(r.url.path,'/rest/v1/daily_report_edit_requests');expect(r.url.queryParameters['id'],'eq.$target');expect(r.url.queryParameters['select'],'id');
    return http.Response(jsonEncode(mode=='forbidden'?{'code':'42501','message':'forbidden'}:mode=='present'?{'id':target}:null),mode=='forbidden'?403:200,headers:{'content-type':'application/json'},request:r);
   }));
   try{
    await client.auth.setInitialSession(session('33333333-3333-4333-8333-333333333333'));await Future<void>.delayed(Duration.zero);
    final result=dailyReportNotificationAvailable(client,target);
    if(mode=='forbidden'){await expectLater(result,throwsA(isA<PostgrestException>()));}
    else{expect(await result,mode=='present');}
    expect(reads,1);
   }finally{await client.dispose();}
  });
 }
 for(final mode in ['missing','forbidden','disappeared']){
  testWidgets('report notice screen $mode preserves history and blocks unrelated navigation',(tester)async{
   var checks=0,opens=0,acknowledgements=0;
   await tester.pumpWidget(MaterialApp(home:NotificationExplanationPage(
    item:const AttentionCenterItem(id:'notice',source:'notification',title:'Saved report notice',body:'Saved historical text',state:AttentionCenterState.unknown,actionKey:'daily_report_edit_request',actionId:target),
    onShown:()async{acknowledgements++;},
    canOpenTarget:()async{
     checks++;
     if(mode=='forbidden')throw StateError('request unavailable');
     return mode=='disappeared'&&checks==1;
    },
    openTarget:(_)async{opens++;},
   )));
   await tester.pumpAndSettle();
   expect(find.text('Saved historical text'),findsOneWidget);expect(acknowledgements,1);
   if(mode=='disappeared'){
    expect(find.text('開く'),findsOneWidget);await tester.ensureVisible(find.text('開く'));await tester.tap(find.text('開く'));await tester.pumpAndSettle();
   }
   expect(find.text('開く'),findsNothing);expect(opens,0);expect(checks,mode=='disappeared'?2:1);expect(tester.takeException(),isNull);
   await tester.pumpWidget(const SizedBox());
  });
 }
}
