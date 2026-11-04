import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/notifications/attention_center_item.dart';
import 'package:sk_works/features/notifications/attention_center_repository.dart';
import 'package:sk_works/features/notifications/app_notification_repository.dart';
import 'package:sk_works/features/notifications/notifications_page.dart';
const actor='11111111-1111-4111-8111-111111111111';
const hint='通知は既読です。必要な確認・承認が完了するまで要対応に残ります。';
class Source implements AttentionCenterRepository{
 Source(this.saved);final bool saved;
 @override Future<AttentionCenterData> load({Set<String>? availableActionKeys,String? companyId,String? Function()? currentCompany})async{
  const item=AttentionCenterItem(id:'synthetic',source:'notification',title:'Pending synthetic task',state:AttentionCenterState.pending,read:true);
  return AttentionCenterData(snapshot:AttentionCenterSnapshot([item],now:DateTime(2026,11,4)),notificationsById:saved?{'notice':AppNotificationRecord(id:'notice',kind:'approval',title:item.title,body:'',createdAt:DateTime(2026,11,4),read:true)}:{},notificationIdsByItemKey:saved?{item.deduplicationKey:['notice']}:{},unavailableSources:{});
 }
 @override dynamic noSuchMethod(Invocation invocation)=>throw StateError('Unexpected repository operation');
}
void main(){
 late SupabaseClient client;
 setUpAll(()async{
   client=SupabaseClient('https://synthetic.invalid','synthetic',authOptions:const AuthClientOptions(autoRefreshToken:false),httpClient:MockClient((_)async=>throw StateError('No network expected')));
   String part(Object value)=>base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=','');
   await client.auth.setInitialSession(jsonEncode({'access_token':'${part({'alg':'HS256'})}.${part({'sub':actor,'exp':4102444800})}.synthetic','refresh_token':'synthetic','token_type':'bearer','expires_in':3600,'user':{'id':actor,'aud':'authenticated','created_at':'2026-01-01T00:00:00Z','app_metadata':{},'user_metadata':{}}}));

 });
 tearDownAll(()async{await client.dispose();});
 for(final saved in [false,true]){
  testWidgets('read explanation requires saved notification identity: $saved',(tester)async{
   await tester.pumpWidget(MaterialApp(home:NotificationsPage(attentionRepository:Source(saved),notificationClient:client)));
   await tester.pumpAndSettle();
   expect(find.text('Pending synthetic task'),findsOneWidget);
   expect(find.text('既読'),saved?findsOneWidget:findsNothing);
   expect(find.text(hint),saved?findsOneWidget:findsNothing);
   expect(tester.takeException(),isNull);
   await tester.pumpWidget(const SizedBox());
  });
 }
}
