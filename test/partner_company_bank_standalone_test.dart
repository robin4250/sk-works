import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/shared/standalone_trade_document_repository.dart';
import 'package:sk_works/features/shared/standalone_trade_document.dart';

const company='10000000-0000-4000-8000-000000000001',partner='10000000-0000-4000-8000-000000000002',actor='10000000-0000-4000-8000-000000000003',trade='10000000-0000-4000-8000-000000000004';
Map<String,dynamic> bank()=>{'schema':1,'company_id':company,'partner_company_id':partner,'bank_version':2,'bank_name':'固定銀行','branch_name':'固定支店','account_type':'普通','account_number':'0000123','account_holder':'ジュチュウカイシャ'};
String session({String sid=trade}) {
 String part(Object value)=>base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=','');
 return jsonEncode({'access_token':'${part({'alg':'HS256'})}.${part({'sub':actor,'session_id':sid,'exp':4102444800})}.${base64Url.encode(List.filled(32,7)).replaceAll('=','')}',
 'refresh_token':'synthetic','expires_in':3600,'token_type':'bearer','user':{'id':actor,'aud':'authenticated','is_anonymous':false,'app_metadata':{},'user_metadata':{},'created_at':'2026-01-01T00:00:00Z'}});
}
class Fixture {
 final calls=<http.Request>[];late SupabaseClient client;late StandaloneTradeDocumentRepository repository;
 bool linked=true;String mode='bank';Completer<http.Response>? pending;
 Future<void> open()async {
  client=SupabaseClient('https://standalone-bank-fixture.invalid','synthetic-public',authOptions:const AuthClientOptions(autoRefreshToken:false),httpClient:MockClient((request)async{
   calls.add(request);expect(request.headers.entries.where((e)=>e.key.toLowerCase()=='authorization').single.value,'Bearer ${jsonDecode(session())['access_token']}');
   final name=request.url.path.split('/').last;Object? value;
   switch(name){
    case 'company_members': value=[{'company_id':company,'role':'admin'}];
    case 'trade_company_contact_workspace': value=[{'id':trade,'trade_role':'both','name':'受注会社','address':'受注住所','representative_name':'乙代表',if(linked)'partner_company_id':partner}];
    case 'read_partner_company_profile': value={'company_id':company,'profile':{'name':'発注会社','address':'発注住所','representative_name':'甲代表'}};
    case 'companies': value={'id':company,'name':'発注会社','company_seal_enabled':false,'company_seal_style':'legacy'};
    case 'company_uploaded_seal_settings':value={'company_id':company,'company_name':'発注会社','enabled':false};
    case 'trade_document_template':value={'payload':{'work_name':'初期工事'}};
    case 'partner_company_bank_read':
     expect(jsonDecode(request.body),{'p_company':company,'p_partner':partner});
     if(pending!=null)return pending!.future;
     if(mode=='absent')return http.Response(jsonEncode({'code':'PGRST202','message':'fixture absent','details':null,'hint':null}),404,headers:{'content-type':'application/json'},request:request);
     value=mode=='null'?null:{'available':mode!='off','company_id':mode=='foreign'?actor:company,'partner_company_id':partner,'version':mode=='off'?0:2,'bank':mode=='off'?null:bank()};
    default:throw StateError('Unexpected fixture request $name');
   }
   return http.Response(jsonEncode(value),200,headers:{'content-type':'application/json'},request:request);
  }));
  await client.auth.setInitialSession(session());repository=StandaloneTradeDocumentRepository(client);
 }
 Future<void> close()async{await repository.dispose();await client.dispose();}
}
Map<String,String> fields()=>{'work_name':'工事','work_address':'東京都','issue_date':'2026-10-29','order_date':'2026-10-29','period_start':'2026-11-01','period_end':'2026-11-30','total_amount_yen':'110000','tax_amount_yen':'10000'};
void main(){
 test('actual SDK canonical supplier link loads exact scoped bank once and builder freezes it',()async{
  final f=Fixture();await f.open();try{
   final context=await f.repository.load(tradeCompanyId:trade,acceptance:false);
   expect(context['counterparty_bank'],bank());expect(context['partner_company_id'],partner);
   final input=fields()..['counterparty_bank.account_number']='9999999';
   final result=standaloneTradeDocument(context:context,fields:input);expect(result.payload['counterparty_bank'],bank());
   (context['counterparty_bank'] as Map)['account_number']='0000999';expect((result.payload['counterparty_bank'] as Map)['account_number'],'0000123');
   (context['counterparty_bank'] as Map)['company_id']=actor;expect(()=>standaloneTradeDocument(context:context,fields:input),throwsFormatException);
   expect(f.calls.where((r)=>r.url.path.endsWith('/partner_company_bank_read')),hasLength(1));
  }finally{await f.close();}
 });
 test('acceptance never reads or copies supplier bank and missing link is never inferred by name',()async{
  final f=Fixture();await f.open();try{
   final acceptance=await f.repository.load(tradeCompanyId:trade,acceptance:true);expect(acceptance.containsKey('counterparty_bank'),false);
   expect(standaloneTradeDocument(context:{...acceptance,'counterparty_bank':bank()},fields:fields()).payload.containsKey('counterparty_bank'),false);
   f.linked=false;final order=await f.repository.load(tradeCompanyId:trade,acceptance:false);expect(order.containsKey('counterparty_bank'),false);
   expect(f.calls.any((r)=>r.url.path.endsWith('/partner_company_bank_read')),false);
  }finally{await f.close();}
 });
 for(final mode in ['off','absent']){
  test('unreleased $mode keeps legacy order bank-free without write',()async{
   final f=Fixture()..mode=mode;await f.open();try{final context=await f.repository.load(tradeCompanyId:trade,acceptance:false);expect(context.containsKey('counterparty_bank'),false);expect(standaloneTradeDocument(context:context,fields:fields()).payload.containsKey('counterparty_bank'),false);expect(f.calls.any((r)=>r.url.path.contains('/save')),false);}finally{await f.close();}
  });
 }
 for(final mode in ['foreign','null']){
  test('malformed $mode authority response refuses instead of treating it as absent',()async{
   final f=Fixture()..mode=mode;await f.open();try{await expectLater(f.repository.load(tradeCompanyId:trade,acceptance:false),throwsStateError);}finally{await f.close();}
  });
 }
 test('SID replacement while bank read is pending rejects old response',()async{
  final f=Fixture();await f.open();try{
   f.pending=Completer<http.Response>();final result=f.repository.load(tradeCompanyId:trade,acceptance:false);final rejected=expectLater(result,throwsStateError);
   for(var i=0;i<100&&!f.calls.any((r)=>r.url.path.endsWith('/partner_company_bank_read'));i++){await Future<void>.delayed(Duration.zero);}
   expect(f.calls.last.url.path,endsWith('/partner_company_bank_read'));await f.client.auth.setInitialSession(session(sid:partner));
   f.pending!.complete(http.Response(jsonEncode({'available':true,'company_id':company,'partner_company_id':partner,'version':2,'bank':bank()}),200,headers:{'content-type':'application/json'},request:f.calls.last));await rejected;
  }finally{await f.close();}
 });
}
