import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/shared/trade_documents_hub_repository.dart';

const actor='10000000-0000-4000-8000-000000000001';
const company='10000000-0000-4000-8000-000000000002';
const party='20000000-0000-4000-8000-000000000001';
const sid='30000000-0000-4000-8000-000000000001';
String token(){String part(Object v)=>base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=','');
 return '${part({'alg':'HS256','typ':'JWT'})}.${part({'sub':actor,'session_id':sid,'role':'authenticated','exp':DateTime.now().millisecondsSinceEpoch~/1000+3600})}.synthetic';}
class _Http extends http.BaseClient {
 final calls=<String>[];
 String role='manager';bool enabled=true,multiple=false,foreignReceipt=false,removeParty=false;
 final bearer=token();
 @override Future<http.StreamedResponse> send(http.BaseRequest r)async{
  calls.add(r.url.path);Object raw;
  if(r.url.path.endsWith('/auth/v1/token')){
   raw={'access_token':bearer,'refresh_token':'fixture','expires_in':3600,'token_type':'bearer',
    'user':{'id':actor,'aud':'authenticated','role':'authenticated','created_at':'2026-01-01T00:00:00Z'}};
  }else if(r.url.path.endsWith('/auth/v1/logout')){raw={};}
  else{
   expect(r.headers['Authorization']??r.headers['authorization'],'Bearer $bearer');
   if(r.url.path.endsWith('/company_members')){
    raw=[{'company_id':company,'role':role},if(multiple){'company_id':party,'role':'owner'}];
   }else if(r.url.path.endsWith('/current_master_feature_flags')){
    raw={'site_order_documents':enabled,'standalone_trade_documents_contract_version':1,'trade_documents_master_contract_version':1};
   }else if(r.url.path.endsWith('/standalone_trade_document_access')){
    raw={'contract_version':1,'actor_id':actor,'company_id':foreignReceipt?party:company,
     'session_id':sid,'role':role,'master_enabled':true,'can_generate':true,'context_contract_version':1};
   }else if(r.url.path.endsWith('/trade_company_contact_workspace')){
    raw=[if(!removeParty){'id':party,'name':'登録会社','trade_role':'both'}];
   }else{throw StateError('Unexpected fixture endpoint');}
  }
  return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(raw))),200,headers:{'content-type':'application/json'});
 }
}
class _Fixture {
 final wire=_Http();late final client=SupabaseClient('https://fixture.invalid','synthetic-public',httpClient:wire,
  authOptions:const AuthClientOptions(autoRefreshToken:false));
 TradeDocumentsHubRepository? repository;
 Future<void> open(WidgetTester t)async{
  t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await t.runAsync(()=>client.auth.signInWithPassword(email:'fixture@example.invalid',password:'fixture-password'));
  repository=TradeDocumentsHubRepository(client);
 }
 Future<TradeDocumentsHubSnapshot> load(WidgetTester t)async=>(await t.runAsync(()=>repository!.load()))!;
 Future<void> close(WidgetTester t)async{repository?.dispose();await t.runAsync(client.dispose);}
}
void main(){
 testWidgets('OFF reads no company directory or privileged registration context',(t)async{
  final f=_Fixture();try{await f.open(t);f.wire.enabled=false;final value=await f.load(t);
   expect(value.availability.enabled,false);expect(value.parties,isEmpty);
   expect(f.wire.calls.any((p)=>p.endsWith('/trade_company_contact_workspace')||p.endsWith('/standalone_trade_document_access')),false);
  }finally{await f.close(t);}
 });
 testWidgets('manager uses exact server receipt and read-only directory',(t)async{
  final f=_Fixture();try{await f.open(t);final value=await f.load(t);
   expect(value.role,'manager');expect(value.companyId,company);expect(value.parties.single.id,party);
   f.repository!.requireOperation(company,party,false);f.repository!.requireOperation(company,party,true);
   expect(f.wire.calls.any((p)=>p.contains('sync_trade_company')||p.contains('read_partner_company_profile')),false);
  }finally{await f.close(t);}
 });
 testWidgets('wrong-company receipt fails before directory and clears any previous snapshot',(t)async{
  final f=_Fixture();try{await f.open(t);await f.load(t);f.wire.calls.clear();f.wire.foreignReceipt=true;
   await t.runAsync(()=>expectLater(f.repository!.load(),throwsStateError));expect(f.repository!.snapshot,isNull);
   expect(f.wire.calls.any((p)=>p.endsWith('/trade_company_contact_workspace')),false);
   expect(()=>f.repository!.requireOperation(company,party,false),throwsStateError);
  }finally{await f.close(t);}
 });
 testWidgets('refresh denies OFF, lost role, removed party and multiple memberships',(t)async{
  for(final reason in ['off','role','party','multiple']){
   final f=_Fixture();try{await f.open(t);await f.load(t);
    if(reason=='off'){f.wire.enabled=false;}
    if(reason=='role'){f.wire.role='employee';}
    if(reason=='party'){f.wire.removeParty=true;}
    if(reason=='multiple'){f.wire.multiple=true;}
    await t.runAsync(()=>expectLater(f.repository!.refreshOperation(company,party,false),throwsStateError));
    expect(()=>f.repository!.requireOperation(company,party,false),throwsStateError);
   }finally{await f.close(t);}
  }
 });
 testWidgets('logout retires captured session and prevents all later reads',(t)async{
  final f=_Fixture();try{await f.open(t);await f.load(t);
   await t.runAsync(()=>f.client.auth.signOut(scope:SignOutScope.local));await t.pump();
   final before=f.wire.calls.length;expect(f.repository!.requireCurrent,throwsStateError);
   await t.runAsync(()=>expectLater(f.repository!.load(),throwsStateError));expect(f.wire.calls.length,before);
  }finally{await f.close(t);}
 });
}
