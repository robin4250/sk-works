import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/attendance/scheduled_checkout_repository.dart';
const actor='00000000-0000-0000-0000-000000000010';
const other='00000000-0000-0000-0000-000000000011';
const company='00000000-0000-0000-0000-000000000001';
const worker='00000000-0000-0000-0000-000000000020';
const source='00000000-0000-0000-0000-000000000040';
const site='00000000-0000-0000-0000-000000000030';
Map<String,dynamic> target({bool due=true}) => {
 'company_id':company,'worker_id':worker,'source_clock_in_id':source,'work_date':'2026-10-25',
 'site_id':site,'route_assignment_id':null,'reminder_at':due?'2026-10-25T08:00:00+00:00':'2026-10-25T09:00:00+00:00',
 'due':due,'can_manage_attendance':false,'scope_fingerprint':'source-version-1',
};
Map<String,dynamic> state({bool due=true})=>{'schema':1,'actor_id':actor,'feature_enabled':true,
 'server_time':'2026-10-25T08:30:00+00:00','items':[target(due:due)]};
Map<String,dynamic> config()=>{'company_id':company,'worker_id':worker,'site_id':site,
 'route_assignment_id':null,'weekdays':[1,2,3,4,5],'clock_in_time':'08:00:00','checkout_time':'17:00:00',
 'checkout_next_day':false,'timezone':'Asia/Tokyo','revision':1,'enabled':true};
Map<String,dynamic> plan()=>{'schema':1,'actor_id':actor,'state':state(due:false),'configurations':[config()],
 'planned_notifications':[{'source_id':'$actor:$source','worker_id':worker,'work_date':'2026-10-25',
 'source_clock_in_id':source,'fire_at':'2026-10-25T09:00:00+00:00'}]};
String token(String uid){
 String p(Object o)=>base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=','');
 return '${p({'alg':'HS256','typ':'JWT'})}.${p({'sub':uid,'role':'authenticated','session_id':uid,'exp':DateTime.now().millisecondsSinceEpoch~/1000+3600})}.fixture';
}
class Fixture{
 String user=actor;bool switchDuringRead=false;final requests=<String>[];final parameters=<Map<String,dynamic>>[];
 late final client=SupabaseClient('https://synthetic.invalid','fixture-only',
  authOptions:const AuthClientOptions(autoRefreshToken:false),httpClient:MockClient(handle));
 late final repository=ScheduledCheckoutRepository(client);
 Future<void> login([String uid=actor])async{user=uid;await client.auth.signInWithPassword(email:'synthetic@example.invalid',password:'fixture-only');await Future<void>.delayed(Duration.zero);}
 Future<http.Response> handle(http.Request req)async{
  Object? value;
  if(req.url.path.endsWith('/token')){value={'access_token':token(user),'refresh_token':'fixture-only','token_type':'bearer','expires_in':3600,
   'user':{'id':user,'aud':'authenticated','role':'authenticated','email':'synthetic@example.invalid','app_metadata':{'provider':'email'},'user_metadata':<String,dynamic>{},'created_at':'2026-10-01T00:00:00Z'}};}
  else{
   requests.add(req.url.path.split('/').last);parameters.add(Map<String,dynamic>.from(jsonDecode(req.body) as Map));
   if(switchDuringRead){switchDuringRead=false;await login(other);await login(actor);}
   value=req.url.path.endsWith('/read_my_scheduled_checkout_notification_plan')?plan():state(due:!req.url.path.endsWith('/postpone_my_scheduled_checkout'));
  }
  return http.Response(jsonEncode(value),200,headers:{'content-type':'application/json'},request:req);
 }
}
void main(){
 test('fresh due state binds real source and destination',(){final s=ScheduledCheckoutRepository.parse(state(),actor);expect(s.due.single.sourceId,source);expect(s.targets.single.canManageAttendance,isFalse);});
 test('future reminder is retained without blocking normal use',(){expect(ScheduledCheckoutRepository.parse(state(due:false),actor).due,isEmpty);});
 test('OFF with no targets is distinct from missing API',(){final s=state()..['feature_enabled']=false..['items']=[];expect(ScheduledCheckoutRepository.parse(s,actor).enabled,isFalse);expect(()=>ScheduledCheckoutRepository.parse({},actor),throwsStateError);});
 test('OFF cannot contain due targets',(){final s=state()..['feature_enabled']=false;expect(()=>ScheduledCheckoutRepository.parse(s,actor),throwsStateError);});
 test('another actor response is rejected',(){expect(()=>ScheduledCheckoutRepository.parse(state(),other),throwsStateError);});
 test('duplicate source is rejected',(){final s=state()..['items']=[target(),target()];expect(()=>ScheduledCheckoutRepository.parse(s,actor),throwsStateError);});
 test('ambiguous site and route is rejected',(){final t=target()..['route_assignment_id']=site;final s=state()..['items']=[t];expect(()=>ScheduledCheckoutRepository.parse(s,actor),throwsStateError);});
 test('invalid calendar day and unknown due state are rejected',(){for(final patch in [{'work_date':'2026-02-31'},{'due':'true'},{'reminder_at':'2026-10-25 08:00:00'}]){final s=state()..['items']=[target()..addAll(patch)];expect(()=>ScheduledCheckoutRepository.parse(s,actor),throwsStateError);}});
 test('same-time config is rejected rather than assuming 24 hours',(){final c=config()..['checkout_time']='08:00:00';expect(()=>ScheduledCheckoutRepository.parseConfigurations({'schema':1,'actor_id':actor,'configurations':[c]},actor),throwsStateError);});
 test('overnight config must explicitly match next-day marker',(){final c=config()..['clock_in_time']='22:00:00'..['checkout_time']='06:00:00'..['checkout_next_day']=true;expect(ScheduledCheckoutRepository.parseConfigurations({'schema':1,'actor_id':actor,'configurations':[c]},actor).single.checkoutNextDay,isTrue);});
 test('notification uses server UTC instant and source-bound key',(){final p=ScheduledCheckoutRepository.parseNotificationPlan(plan(),actor);expect(p.plannedNotifications.single.fireAt,DateTime.utc(2026,10,25,9));});
 test('notification cannot change clock source or time',(){for(final patch in [{'source_id':'$other:$source'},{'source_clock_in_id':site},{'fire_at':'2026-10-25T10:00:00Z'}]){final p=plan();(p['planned_notifications'] as List).first.addAll(patch);expect(()=>ScheduledCheckoutRepository.parseNotificationPlan(p,actor),throwsStateError);}});
 test('session missing never sends an RPC',()async{final f=Fixture();addTearDown(f.client.dispose);await expectLater(f.repository.read(),throwsStateError);expect(f.requests,isEmpty);});
 test('read and postpone pass exact source CAS, never clockout RPC',()async{final f=Fixture();addTearDown(f.client.dispose);await f.login();final before=await f.repository.read();expect((await f.repository.postpone(before.due.single)).due,isEmpty);expect(f.requests,['read_my_scheduled_checkout','postpone_my_scheduled_checkout']);expect(f.parameters.last,{'p_source_clock_in_id':source,'p_expected_scope':'source-version-1'});});
 test('A to B to A in-flight auth events reject old response',()async{final f=Fixture();addTearDown(f.client.dispose);await f.login();final original=f.client.auth.currentSession!.accessToken;f.switchDuringRead=true;await expectLater(f.repository.read(),throwsStateError);expect(f.client.auth.currentSession!.accessToken,original);});
 test('native notification plan is one session-scoped RPC',()async{final f=Fixture();addTearDown(f.client.dispose);await f.login();expect((await f.repository.loadNotificationPlan()).actorId,actor);expect(f.requests,['read_my_scheduled_checkout_notification_plan']);});
}
