import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/tutorial/tutorial_evidence_repository.dart';
import 'package:sk_works/features/tutorial/tutorial_workspace.dart';
import 'package:sk_works/features/notifications/attention_center_repository.dart';
import 'package:sk_works/features/notifications/attention_center_item.dart';
import 'package:sk_works/features/notifications/required_document_evidence.dart';

const actor='10000000-0000-0000-0000-000000000001';
const company='10000000-0000-0000-0000-000000000002';
const worker='10000000-0000-0000-0000-000000000003';
const sidA='10000000-0000-0000-0000-000000000004';
const sidB='10000000-0000-0000-0000-000000000005';
const requirement='10000000-0000-0000-0000-000000000006';
const additional='10000000-0000-0000-0000-000000000007';
Map<String,dynamic> item(String id,String name,String state,{String scope='internal',String label=''})=>{
 'requirement_id':id,'name':name,'scope':scope,'state':state,
 'evidence_key':state=='saved'?'synthetic:$id':null,'status_label':label};
Map<String,dynamic> receipt(List<Map<String,dynamic>> items,{String sid=sidA})=>{
 'capability_version':1,'evidence_contract_version':1,'company_id':company,'worker_id':worker,'actor_id':actor,'session_id':sid,
 'items':items,'required_count':items.where((i)=>i['state']!='exempt').length,
 for(final state in ['saved','missing','unknown','exempt']) '${state}_count':items.where((i)=>i['state']==state).length,
 for(final state in ['missing','unknown']) '${state}_names':items.where((i)=>i['state']==state).map((i)=>i['name']).toList(),
};
TutorialWorkspace workspace(Map raw)=>TutorialWorkspace.fromSnapshot(TutorialEvidenceSnapshot(role:'employee',tasks:[
 TutorialEvidenceTask(key:'required_documents',actionKey:'document_register',checkpoints:
  TutorialEvidenceRepository.documentCheckpoints({'canonical_evidence':raw},today:DateTime(2099,1,1)))]));
void equalCounts(Map raw){final evidence=RequiredDocumentEvidenceSnapshot.fromJson(raw);final guide=workspace(raw);
 final attention=AttentionCenterSnapshot(mapRequiredDocumentAttention(raw),now:DateTime(2026,10,31));
 expect(guide.progress.required.total,evidence.requiredCount);expect(guide.progress.required.completed,evidence.savedCount);
 expect(guide.progress.required.missing,evidence.missingCount);expect(guide.progress.required.unknown,evidence.unknownCount);
 expect(attention.unresolvedCount,evidence.missingCount);
 expect(attention.items.where((i)=>i.state==AttentionCenterState.unknown).length,evidence.unknownCount);
}
class Wire {
 String sid=sidA;bool unavailable=false;String? returnedCompany;
 List<Map<String,dynamic>> items=[item(requirement,'雇用保険被保険者証','missing',label:'添付待ち')];
 final requests=<http.Request>[];Completer<void>? entered,release;
 final expiry=DateTime.now().millisecondsSinceEpoch~/1000+3600;
 late final client=SupabaseClient('https://synthetic.invalid','synthetic-public',authOptions:const AuthClientOptions(autoRefreshToken:false),httpClient:MockClient(respond));
 String token(String id){String part(Object v)=>base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=','');
  return '${part({'alg':'HS256'})}.${part({'sub':actor,'role':'authenticated','session_id':id,'exp':expiry})}.synthetic';}
 Future<void> login(String id)async{sid=id;await client.auth.signInWithPassword(email:'synthetic@example.invalid',password:'synthetic');await Future<void>.delayed(Duration.zero);}
 Future<http.Response> respond(http.Request request)async{requests.add(request);Object? value;var status=200;
  switch(request.url.path){
   case '/auth/v1/token':value={'access_token':token(sid),'refresh_token':'synthetic','expires_in':3600,'token_type':'bearer',
    'user':{'id':actor,'aud':'authenticated','role':'authenticated','email':'synthetic@example.invalid','app_metadata':{},'user_metadata':{},'created_at':'2026-10-31T00:00:00Z'}};
   case '/rest/v1/company_members':value=[{'company_id':company,'role':'employee'}];
   case '/rest/v1/rpc/current_user_required_document_attention_for_company':
    final captured=sid;entered?.complete();if(release!=null){await release!.future;}
    if(unavailable){status=404;value={'code':'PGRST202','message':'scoped capability unavailable'};}
    else{value={...receipt(items,sid:captured),if(returnedCompany!=null)'company_id':returnedCompany};}
   default:throw StateError('Unexpected private metadata query ${request.url.path}');
  }
  return http.Response(jsonEncode(value),status,headers:{'content-type':'application/json'},request:request);
 }
 Future<TutorialEvidenceSnapshot> load()=>TutorialEvidenceRepository.forClient(client,companyId:company)
  .load(availableActionKeys:{'document_register'});
}
void main(){TestWidgetsFlutterBinding.ensureInitialized();
 test('guide and attention preserve same-name different-scope obligations by requirement ID',(){
  final raw=receipt([item(requirement,'同名書類','missing'),item(additional,'同名書類','missing',scope:'upstream')]);
  equalCounts(raw);final pending=mapRequiredDocumentAttention(raw);
  expect(pending.length,2);expect(pending.map((i)=>i.id).toSet().length,2);
  expect(pending.map((i)=>i.title).toSet().length,2);
 });
 test('exemption, saved bank metadata, unknown and health expiry use one receipt',(){
  for(final state in ['saved','missing','unknown','exempt']){
   final raw=receipt([item(requirement,'銀行口座情報',state,label:state=='exempt'?'免除':'口座情報を確認')]);
   equalCounts(raw);expect(workspace(raw).canCompleteInitial,state=='saved'||state=='exempt');
  }
  equalCounts(receipt([item(requirement,'健康診断書','missing',label:'登録済み・期限未入力')]));
 });
 test('production guide SDK uses the canonical receipt and never queries private bank/photos directly',()async{
  final f=Wire();addTearDown(f.client.dispose);await f.login(sidA);f.requests.clear();
  final snapshot=await f.load();expect(snapshot.tasks.single.checkpoints.single.statusLabel,'添付待ち');
  expect(f.requests.map((r)=>r.url.path),['/rest/v1/company_members','/rest/v1/company_members','/rest/v1/rpc/current_user_required_document_attention_for_company']);
  expect(f.requests.every((r)=>r.headers['Authorization']=='Bearer ${f.token(sidA)}'),isTrue);
  expect(jsonDecode(f.requests.last.body),{'p_company_id':company});
  f.items=[item(requirement,'雇用保険被保険者証','exempt',label:'免除'),item(additional,'新しい必要書類','missing')];
  final updated=TutorialWorkspace.fromSnapshot(await f.load());expect(updated.progress.required.total,1);
  expect(updated.progress.required.missing,1);expect(updated.canCompleteInitial,isFalse);
 });
 test('unavailable or mismatched canonical receipt is unknown without legacy fallback',()async{
  final f=Wire();addTearDown(f.client.dispose);await f.login(sidA);f.unavailable=true;
  var snapshot=await f.load();expect(snapshot.tasks.single.checkpoints.single.state,TutorialEvidenceState.unknown);
  f.unavailable=false;f.returnedCompany='10000000-0000-0000-0000-000000000099';
  snapshot=await f.load();expect(snapshot.tasks.single.checkpoints.single.state,TutorialEvidenceState.unknown);
  expect(f.requests.any((r)=>r.url.path.endsWith('/current_user_required_document_attention')),isFalse);
 });
 test('guide discards an old receipt across SID A B A',()async{
  final f=Wire()..entered=Completer<void>()..release=Completer<void>();addTearDown(f.client.dispose);await f.login(sidA);
  final pending=f.load();final check=expectLater(pending,throwsStateError);await f.entered!.future;
  await f.login(sidB);await f.login(sidA);f.release!.complete();await check;
 });
 final fixture=Platform.environment['SKO_CANONICAL_RECEIPTS_FIXTURE'];
 if(fixture!=null){test('actual Native PostgreSQL receipts parse and drive matching guide/home counts',(){
  final rows=jsonDecode(File(fixture).readAsStringSync()) as List;expect(rows.length,greaterThan(5));
  for(final raw in rows){equalCounts(raw as Map);}
 });}
}
