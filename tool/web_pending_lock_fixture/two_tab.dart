// ignore_for_file: depend_on_referenced_packages
// Local-only manual two-tab fixture. No backend accounts or external transport.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_web/shared_preferences_web.dart';
import 'package:web/web.dart' as web;
import 'package:sk_works/features/profile/personal_pending_admission.dart';
import 'main.dart' as f;

@JS('Object.defineProperty') external JSObject defineProperty(JSObject object, JSString name, JSObject descriptor);
@JS('Object.getOwnPropertyDescriptor') external JSAny? ownDescriptor(JSObject object, JSString name);
@JS('Reflect.deleteProperty') external JSBoolean deleteProperty(JSObject object, JSString name);
void main(){WidgetsFlutterBinding.ensureInitialized();SharedPreferencesPlugin.registerWith(null);runApp(MaterialApp(theme:ThemeData(fontFamily:'SkoWebUI'),home:const TwoTabFixture()));}
class TwoTabFixture extends StatefulWidget{const TwoTabFixture({super.key});@override State<TwoTabFixture> createState()=>_State();}
class _State extends State<TwoTabFixture>{
 String status='READY — LOCAL SYNTHETIC ONLY';Completer<void>? release;Future<void>? holder;bool running=false;
 void show(String value){if(mounted)setState(()=>status=value);}
 Future<void> checkAction(Future<void> Function() action)async{if(running)return;setState(()=>running=true);try{await action();}catch(_){show('FAIL: fixed fixture assertion; no raw details');}finally{if(mounted)setState(()=>running=false);}}
 Future<void> hold()async{
  if(holder!=null)return;
  release=Completer<void>();final entered=Completer<void>();
  holder=withPersonalPendingAdmission(f.actor,()async{entered.complete();show('A LOCK_HELD — open another tab, press Contend');await release!.future;show('A LOCK_RELEASED');});
  // Attach a handler immediately; no unhandled future if API is unavailable.
  unawaited(holder!.catchError((Object _){if(!entered.isCompleted)entered.completeError(StateError('unavailable'));show('LOCK_UNAVAILABLE — body never entered');}));
  await entered.future.timeout(const Duration(seconds:3));
 }
 Future<void> contend()async{
  bool entered=false,refused=false;
  try{await withPersonalPendingAdmission(f.actor,()async{entered=true;});}
  on StateError catch(e){refused=e.message=='別のタブで保存処理中です。結果を確認してから操作してください。';}
  f.check(refused&&!entered,'literal other-tab busy must prevent body');show('B PASS BUSY; BODY=0');
 }
 Future<void> unknown()async{
  final x=f.Fixture();await x.init();try{await x.repo.load();await x.ambiguity();f.check(x.saves==1&&x.repo.pendingUnknown,'one unknown send');show('A UNKNOWN_PERSISTED; save RPC=1; lock released');}finally{await x.close();}
 }
 Future<void> observeUnknown()async{
  final x=f.Fixture();await x.init();try{await x.repo.load();f.check(x.repo.pendingUnknown,'other tab observes pending');bool refused=false;try{await x.repo.save(0,{'birth_date':null},f.op,(_,_)async{throw StateError('proof should not run');});}on StateError catch(e){refused=e.message=='保存条件を確認してください。';}f.check(refused&&x.saves==0,'pending prevents second send');f.check(!await x.repo.reconcile(),'unknown retained');f.check(web.window.localStorage.getItem(f.browserKey)!=null,'metadata retained');show('B PASS UNKNOWN_RETAINED; save RPC=0; no replay');}finally{await x.close();}
 }
 Future<void> seedForeign()async{
  await withPersonalPendingAdmission(f.actor,()async{
   final p=await SharedPreferences.getInstance();await p.reload();f.check(p.getString(f.key)==null,'explicit cleanup first');
   final value={'actor':f.actor,'sid':'20000000-0000-4000-8000-000000000002','before':0,'operation':f.op,'digest':f.digest};
   f.check(await p.setString(f.key,jsonEncode(value)),'foreign synthetic persist');
  });show('A FOREIGN_SID_METADATA_SEEDED — no token saved');
 }
 Future<void> observeForeign()async{
  final x=f.Fixture();await x.init();try{await x.repo.load();f.check(x.repo.pendingUnknown,'foreign pending quarantines');await f.unconfirmed(x.repo.reconcile());f.check(x.saves==0&&f.disk()['sid']!=f.sid,'foreign SID remains');show('B PASS FOREIGN_SID_QUARANTINED; no save/reconcile replay');}finally{await x.close();}
 }
 Future<void> unsupported()async{
  final navigator=web.window.navigator;final name='locks'.toJS;final descriptor=ownDescriptor(navigator,name);bool bodyRan=false,denied=false;
  try{
   // Fault injection in this disposable fixture window only; no browser setting.
   defineProperty(navigator,name,{'value':null,'configurable':true}.jsify() as JSObject);
   try{await withPersonalPendingAdmission(f.actor,()async{bodyRan=true;});}on StateError{denied=true;}
   f.check(denied&&!bodyRan,'missing lock manager must fail closed');
  }finally{if(descriptor==null){f.check(deleteProperty(navigator,name).toDart,'restore navigator');}else{defineProperty(navigator,name,descriptor as JSObject);}}
  show('PASS injected unavailable API; BODY=0; manager restored. Not real unsupported browser.');
 }
 Future<void> cleanup()async{await withPersonalPendingAdmission(f.actor,()async{await f.reset();});show('CLEANUP PASS exact synthetic key absent');}
 @override void dispose(){if(release?.isCompleted==false)release!.complete();super.dispose();}
 @override Widget build(BuildContext context)=>Scaffold(body:SafeArea(child:SingleChildScrollView(child:Padding(padding:const EdgeInsets.all(24),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
 const Text('LITERAL TWO-TAB FIXTURE — same localhost origin; synthetic only'),SelectableText(status),
 FilledButton(onPressed:running?null:()=>checkAction(hold),child:const Text('Hold actor lock')),
 FilledButton(onPressed:()=>release?.isCompleted==false?release!.complete():null,child:const Text('Release actor lock')),
 FilledButton(onPressed:running?null:()=>checkAction(contend),child:const Text('Contend from other tab')),
 FilledButton(onPressed:running?null:()=>checkAction(unknown),child:const Text('Create unknown metadata')),
 FilledButton(onPressed:running?null:()=>checkAction(observeUnknown),child:const Text('Observe unknown from other tab')),
 FilledButton(onPressed:running?null:()=>checkAction(seedForeign),child:const Text('Seed foreign SID metadata')),
 FilledButton(onPressed:running?null:()=>checkAction(observeForeign),child:const Text('Observe foreign SID')),
 FilledButton(onPressed:running?null:()=>checkAction(cleanup),child:const Text('Cleanup exact synthetic key')),
 FilledButton(onPressed:running?null:()=>checkAction(unsupported),child:const Text('Inject unavailable API')) ,
 const Text('Unsupported API runtime needs separate negative environment. No production, cross-device or malicious-client enforcement qualification.')])))));
}
