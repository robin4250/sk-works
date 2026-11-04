import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/notifications/app_notification_repository.dart';
import 'package:sk_works/features/notifications/notification_business_status.dart';
const actor='11111111-1111-4111-8111-111111111111';
const invoice='22222222-2222-4222-8222-222222222222';
String session(String sid){
 String part(Object x)=>base64Url.encode(utf8.encode(jsonEncode(x))).replaceAll('=','');
 return jsonEncode({'access_token':'${part({'alg':'HS256'})}.${part({'sub':actor,'role':'authenticated','session_id':sid,'exp':4102444800})}.synthetic', 'refresh_token':'synthetic','token_type':'bearer','expires_in':3600,'user':{'id':actor,'aud':'authenticated','created_at':'2026-01-01T00:00:00Z','app_metadata':{},'user_metadata':{}}});
}
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 for(final mode in ['pending','finalized','unavailable','session_switch','session_aba']){
  test('SDK notification enrichment $mode uses read-only v2 without approval writes',()async{
   final calls=<String>[];final started=Completer<void>();final hold=Completer<void>();
   final client=SupabaseClient('https://synthetic.invalid','synthetic',authOptions:const AuthClientOptions(autoRefreshToken:false),httpClient:MockClient((r)async{
    calls.add('${r.method} ${r.url.path}');Object body=[];var code=200;
    switch(r.url.path){
     case '/rest/v1/rpc/enqueue_due_invoice_approval_notifications':break;
     case '/rest/v1/app_notifications':body=[{'id':'33333333-3333-4333-8333-333333333333','kind':'approval','title':'Synthetic','body':'','action_key':'invoice_approval','action_id':invoice,'created_at':'2026-11-01T00:00:00Z','read_at':'2026-11-02T00:00:00Z'}];break;
     case '/rest/v1/invoices':body=[{'approval_finalized_at':mode=='finalized'?'2026-11-01T00:00:00Z':null,'billing_period_start':'2026-10-01'}];break;
     case '/rest/v1/rpc/invoice_approval_status_rows_v2':
      expect(jsonDecode(r.body),{'p_invoice_id':invoice});
      if(mode.startsWith('session_')){started.complete();await hold.future;}
      if(mode=='unavailable'){code=404;body={'code':'PGRST202','message':'unavailable'};}else{body=[{'approver_user_id':actor,'status':'pending','can_current_user_approve':true}];}break;
     default:throw StateError('Unexpected endpoint: ${r.url.path}');
    }
    return http.Response(jsonEncode(body),code,headers:{'content-type':'application/json'},request:r);
   }));
   try{
    await client.auth.setInitialSession(session('44444444-4444-4444-8444-444444444444'));
    await Future<void>.delayed(Duration.zero);
    final pending=AppNotificationRepository.forTesting(client).load();
    if(mode.startsWith('session_')){
     await started.future.timeout(const Duration(seconds:5));
     await client.auth.setInitialSession(session('55555555-5555-4555-8555-555555555555'));
     if(mode=='session_aba') await client.auth.setInitialSession(session('44444444-4444-4444-8444-444444444444'));
     hold.complete();
    }
    final rows=await pending;
    expect(rows.single.read,isTrue);
    expect(rows.single.businessStatus.state,mode=='pending'?NotificationBusinessState.pending:mode=='finalized'?NotificationBusinessState.completed:NotificationBusinessState.unknown);
    expect(calls.where((x)=>x.contains('invoice_approval_status_rows_v2')).length,mode=='finalized'?0:1);
    expect(calls.any((x)=>x.endsWith('/invoice_approval_status_rows')),isFalse);
    expect(calls.any((x)=>x.startsWith('PATCH ')||x.contains('/approve_invoice')),isFalse);
   }finally{await client.dispose();}
  });
 }
}
