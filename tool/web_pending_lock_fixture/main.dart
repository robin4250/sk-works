// Isolated browser storage fixture; no production defines or actual Auth calls.
// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'dart:async';
import 'package:sk_works/features/profile/personal_pending_admission.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_web/shared_preferences_web.dart';
import 'package:web/web.dart' as web;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/profile/personal_details_repository.dart';
const actor='10000000-0000-0000-0000-000000000001';
const sid='20000000-0000-4000-8000-000000000001';
const op='30000000-0000-4000-8000-000000000001';
const digest='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const key='sko.personal_details.pending.v1.$actor',browserKey='flutter.$key';
final realWeb=SharedPreferencesPlugin();
void check(bool ok,String fixed){if(!ok)throw StateError(fixed);}
Future<void> unconfirmed(Future<Object?> f)async{try{await f;}on PersonalDetailsUnconfirmed{return;}throw StateError('expected unconfirmed');}
Map<String,dynamic> session(){String part(Object v)=>base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=','');return {'access_token':'${part({'alg':'HS256'})}.${part({'sub':actor,'role':'authenticated','session_id':sid,'exp':DateTime.now().millisecondsSinceEpoch~/1000+3600})}.synthetic','refresh_token':'synthetic-$sid','token_type':'bearer','expires_in':3600,'user':{'id':actor,'aud':'authenticated','created_at':'2026-10-29T00:00:00Z','app_metadata':<String,dynamic>{},'user_metadata':<String,dynamic>{}}};}
class DenyPendingWrite extends SharedPreferencesStorePlatform{
 @override Future<Map<String,Object>> getAll()=>realWeb.getAll();
 @override Future<bool> remove(String key)=>realWeb.remove(key);
 @override Future<bool> clear()=>throw StateError('never clear an origin');
 @override Future<bool> setValue(String type,String key,Object value)=>key==browserKey?Future.value(false):realWeb.setValue(type,key,value);
}
class Fixture{
 late SupabaseClient client;late PersonalDetailsRepository repo;int saves=0;bool applied=false;
 Map<String,dynamic> base(int rev)=>{'protocol_version':1,'actor_id':actor,'session_id':sid,'revision':rev};
 Future<void> init()async{
  client=SupabaseClient('https://browser-pending.fixture.invalid','synthetic-not-a-platform-key',authOptions:const AuthClientOptions(autoRefreshToken:false),httpClient:MockClient((r)async{
   final args=jsonDecode(r.body) as Map;check(args['p_expected_session']==sid,'expected synthetic SID');final name=r.url.path.split('/').last;Map<String,dynamic> value;
   switch(name){
    case 'personal_details_summary_v1':value={...base(0),'record_exists':false,'birth_date':null,'bank_registered':false,'updated_at':null};
    case 'personal_details_prepare_save_v1':value={...base(0),'operation_id':op,'input_sha256':digest};
    case 'personal_details_save_v1':saves++;check(web.window.localStorage.getItem(browserKey)!=null,'browser fence before dispatch');throw http.ClientException('synthetic unknown result');
    case 'personal_details_reconcile_v1':value={...base(applied?1:0),'operation_id':op,'input_sha256':digest,'outcome':applied?'applied':'unknown'};
    default:throw StateError('unexpected fixture RPC');
   }
   return http.Response(jsonEncode(value),200,headers:{'content-type':'application/json'},request:r);
  }));await client.auth.setInitialSession(jsonEncode(session()));repo=PersonalDetailsRepository.forClient(client);
 }
 Future<void> ambiguity()=>unconfirmed(repo.save(0,{'birth_date':'2000-01-01'},op,(_,_)async=>'b'*64));
 Future<void> close()async{await repo.close();await client.dispose();}
}
Map<String,dynamic> disk(){final raw=web.window.localStorage.getItem(browserKey);check(raw!=null,'expected actual browser metadata');return Map<String,dynamic>.from(jsonDecode(jsonDecode(raw!)) as Map);}
Future<void> reset()async{SharedPreferencesStorePlatform.instance=realWeb;final p=await SharedPreferences.getInstance();await p.remove(key);await p.reload();check(web.window.localStorage.getItem(browserKey)==null,'synthetic key cleanup');}
Future<void> main()async{
 WidgetsFlutterBinding.ensureInitialized();SharedPreferencesPlugin.registerWith(null);
 final completed=<String>[];String state='running';
 void show()=>runApp(MaterialApp(theme:ThemeData(fontFamily:"SkoWebUI"),home:Scaffold(body:SafeArea(child:SingleChildScrollView(child:Padding(padding:const EdgeInsets.all(24),child:SelectableText('WEB STORAGE FIXTURE\n$state\n${completed.join('\n')}\nNo production connection. Synthetic only. Auth session storage NOT tested.')))))));
 show();
 try{
  await reset();final f=Fixture();await f.init();try{await f.repo.load();await f.ambiguity();final m=disk();check(m.length==5&&m.keys.every({'actor','sid','before','operation','digest'}.contains),'exact metadata keys');check(!jsonEncode(m).contains('2000-01-01')&&!m.containsKey('proof')&&!m.containsKey('access_token'),'no raw secret/data');await f.repo.close();await(await SharedPreferences.getInstance()).reload();f.repo=PersonalDetailsRepository.forClient(f.client);await f.repo.load();check(f.repo.pendingUnknown,'reconstructed pending fence');try{await f.repo.save(0,{'birth_date':null},op,(_,_)async=>'b'*64);throw StateError('resave allowed');}on StateError catch(e){check(e.message!='resave allowed','repeated write denied');}check(f.saves==1,'one save dispatch');completed.add('1 PASS actual metadata-only persistence/new repository');}finally{await f.close();await reset();}
  final g=Fixture();await g.init();try{await g.ambiguity();check(!await g.repo.reconcile(),'unknown retained');check(web.window.localStorage.getItem(browserKey)!=null,'actual stored unknown');g.applied=true;check(await g.repo.reconcile(),'applied confirmed');check(web.window.localStorage.getItem(browserKey)==null&&g.saves==1,'clear without replay');completed.add('2 PASS unknown/applied reconcile, no replay');}finally{await g.close();await reset();}
  final h=Fixture();await h.init();try{SharedPreferencesStorePlatform.instance=DenyPendingWrite();await h.ambiguity();check(h.saves==0&&h.repo.pendingUnknown,'denied write no dispatch');check(web.window.localStorage.getItem(browserKey)==null,'denied browser persistence');completed.add('3 PASS injected write-denial, not actual quota test');}finally{await h.close();await reset();}
  final j=Fixture();await j.init();try{await j.repo.load();final m={'actor':actor,'sid':sid,'before':0,'operation':op,'digest':digest};await realWeb.setValue('String',browserKey,jsonEncode(m));check(disk()['operation']==op,'backend actual write');await j.repo.load();check(j.repo.pendingUnknown&&j.saves==0,'repository refresh sees external fence');bool refused=false;await j.repo.save(0,{'birth_date':null},op,(_,_)async{throw StateError('proof must not be requested');}).then((_){}).onError((Object e,StackTrace _){if(e is StateError&&e.message=='保存条件を確認してください。'){refused=true;return;}throw e;});check(refused,'pending save refused before proof');check(j.saves==0,'external fence blocks dispatch');completed.add('4 PASS external metadata visible before save; cross-tab exclusion STILL UNQUALIFIED');}finally{await j.close();await reset();}
  final entered=Completer<void>(),release=Completer<void>();bool secondRan=false;
  final first=withPersonalPendingAdmission(actor,()async{entered.complete();await release.future;return 1;});
  await entered.future.timeout(const Duration(seconds:3));
  try{await withPersonalPendingAdmission(actor,()async{secondRan=true;return 2;});throw StateError('busy admission accepted');}
  on StateError catch(e){check(e.message!='busy admission accepted','busy admission rejected');}
  check(!secondRan,'busy body never ran');release.complete();check(await first==1,'first future complete');
  check(await withPersonalPendingAdmission(actor,()async=>3)==3,'release after whole future');
  completed.add('5 PASS same-context lock contention/body0/release; literal two tabs NOT tested');
  final k=Fixture();await k.init();try{await k.ambiguity();final replacement={...disk(),'operation':'30000000-0000-4000-8000-000000000002'};await realWeb.setValue('String',browserKey,jsonEncode(replacement));k.applied=true;await unconfirmed(k.repo.reconcile());check(disk()['operation']==replacement['operation']&&k.saves==1,'mismatched metadata retained; no replay');completed.add('6 PASS exact reconcile metadata mismatch retained');}finally{await k.close();await reset();}
  state='DONE: 6 bounded checks PASS. Literal two-tab/unsupported API runtime NOT qualified.';
 }catch(_){state='FAILED: fixture check before case ${completed.length+1}; no raw errors shown';try{await reset();}catch(_){state+='; cleanup unconfirmed';}}
 show();
}
