import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/shared/standalone_trade_document_managed_context.dart';
import 'package:sk_works/features/shared/standalone_trade_document_repository.dart';
import 'package:sk_works/features/shared/trade_document_form_session.dart';

const actor='10000000-0000-4000-8000-000000000001';
const company='10000000-0000-4000-8000-000000000002';
const trade='20000000-0000-4000-8000-000000000001';
const sid='30000000-0000-4000-8000-000000000001';
const partner='40000000-0000-4000-8000-000000000001';
Map<String,dynamic> receipt({bool acceptance=false})=>{
 'context_contract_version':1,'actor_id':actor,'session_id':sid,'company_id':company,'trade_company_id':trade,'acceptance':acceptance,
 'issuer':{'name':'Synthetic issuer','address':'Synthetic address','corporate_number':'','representative_name':'Synthetic representative','phone':'03-1111-2222','fax':'03-3333-4444'},
 'counterparty':{'name':'Synthetic recipient','address':'Synthetic address','corporate_number':'','representative_name':'Synthetic representative','phone':''},
 'template':{'work_name':'Synthetic work','work_address':'Synthetic place','auto_generate':false},
 'company_seal_snapshot':{'version':1,'style':'legacy','name':'Synthetic issuer','company_id':company},
 'company_seal_enabled':true,'bank_backend_available':false};
Map<String,dynamic> parse(Object? v,{bool acceptance=false})=>managedTradeDocumentContext(v,actorId:actor,sessionIdentity:'$actor/$sid',
 companyId:company,tradeCompanyId:trade,acceptance:acceptance);
Map<String,dynamic> bank()=>{'schema':1,'company_id':company,'partner_company_id':partner,'bank_version':1,
 'bank_name':'Synthetic bank','branch_name':'Synthetic branch','account_type':'普通','account_number':'1234567','account_holder':'SYNTHETIC'};
String token(){String part(Object v)=>base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=','');
 return '${part({'alg':'HS256','typ':'JWT'})}.${part({'sub':actor,'session_id':sid,'role':'authenticated','exp':DateTime.now().millisecondsSinceEpoch~/1000+3600})}.synthetic';}
void main(){
 final binding=TestWidgetsFlutterBinding.ensureInitialized();
 setUp(()=>binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));
 test('dedicated context accepts exact scoped receipt and retains configured auto OFF without rewriting it',(){
  final raw=receipt(),value=parse(raw);expect(value,raw);expect(value['template']['auto_generate'],isFalse);
  raw['issuer']['name']='changed after receipt';expect(value['issuer']['name'],'Synthetic issuer');
  expect(value.containsKey('counterparty_bank'),isFalse);expect(value['bank_backend_available'],isFalse);
 });
 for(final field in ['context_contract_version','actor_id','session_id','company_id','trade_company_id','acceptance']){
  test('wrong or absent $field cannot authorize registration',(){
   final wrong=receipt()..[field]=field=='acceptance'?true:field=='context_contract_version'?2:'90000000-0000-4000-8000-000000000001';
   expect(()=>parse(wrong),throwsStateError);expect(()=>parse(receipt()..remove(field)),throwsStateError);
  });
 }
 test('unknown top, party and template fields do not extend the contract implicitly',(){
  expect(()=>parse(receipt()..['admin']=true),throwsStateError);
  var p=receipt();p['issuer']['secret']='unrelated';expect(()=>parse(p),throwsStateError);
  p=receipt();p['counterparty']['fax']='unexpected';expect(()=>parse(p),throwsStateError);
  p=receipt();p['template']['issuer']={'name':'forged'};expect(()=>parse(p),throwsStateError);
  p=receipt();p['template']['auto_generate']='true';expect(()=>parse(p),throwsStateError);
 });
 test('issuer registered seal is tied to exact company, name and known metadata',(){
  for(final patch in [<String,dynamic>{'company_id':trade},{'name':'Other issuer'},{'extra':true},{'version':3}]){
   final p=receipt();p['company_seal_snapshot'].addAll(patch);expect(()=>parse(p),throwsStateError);
  }
 });
 test('optional bank requires explicit availability and exact canonical supplier scope',(){
  final p=receipt()..['partner_company_id']=partner..['bank_backend_available']=true..['counterparty_bank']=bank();
  expect(parse(p)['counterparty_bank'],bank());
  expect(()=>parse({...p,'bank_backend_available':false}),throwsStateError);
  expect(()=>parse({...p,'partner_company_id':trade}),throwsFormatException);
  expect(()=>parse({...p,'counterparty_bank':null}),throwsStateError);
  expect(()=>parse({...p,'partner_company_id':null}),throwsStateError);
  expect(()=>parse(receipt(acceptance:true)..['partner_company_id']=partner,acceptance:true),throwsStateError);
 });
 test('control characters, oversized fields and malformed corporate numbers are rejected without truncation',(){
  for(final pair in [('name','x'*241),('representative_name','x'*81),('phone','x\n'),('corporate_number','１２３４５６７８９０１２３')]){
   final p=receipt();p['issuer'][pair.$1]=pair.$2;expect(()=>parse(p),throwsStateError);
  }
 });
 for(final failure in ['PGRST202','42883','42501','21000','wrong_sid',null]){
  test('managed SDK load uses only dedicated RPC, with no legacy fallback ($failure)',()async{
   final calls=<String>[];final jwt=token();
   final transport=MockClient((r)async{
    if(r.url.path.endsWith('/auth/v1/token'))return http.Response(jsonEncode({'access_token':jwt,'refresh_token':'synthetic-refresh','expires_in':3600,'token_type':'bearer',
     'user':{'id':actor,'aud':'authenticated','role':'authenticated','created_at':'2026-01-01T00:00:00Z'}}),200,headers:{'content-type':'application/json'});
    calls.add(r.url.path);expect(r.url.path,endsWith('/rpc/standalone_trade_document_registration_context'));
    expect(jsonDecode(r.body),{'p_trade_company_id':trade,'p_acceptance':false});
    expect(r.headers['Authorization']??r.headers['authorization'],'Bearer $jwt');
    if(failure!=null&&failure!='wrong_sid')return http.Response(jsonEncode({'code':failure,'message':'Synthetic denial'}),failure=='PGRST202'?404:403,headers:{'content-type':'application/json'});
    final v=receipt();if(failure=='wrong_sid')v['session_id']='90000000-0000-4000-8000-000000000001';
    return http.Response(jsonEncode(v),200,headers:{'content-type':'application/json'});
   });
   final client=SupabaseClient('https://synthetic.invalid','synthetic-public',httpClient:transport,authOptions:const AuthClientOptions(autoRefreshToken:false));
   TradeDocumentFormSession? scope;StandaloneTradeDocumentRepository? repository;
   try{
    await client.auth.signInWithPassword(email:'synthetic@example.invalid',password:'synthetic-password');
    scope=TradeDocumentFormSession(client);repository=StandaloneTradeDocumentRepository(client,session:scope,managedCompanyId:company);
    if(failure==null){expect((await repository.load(tradeCompanyId:trade,acceptance:false))['company_id'],company);}
    else{await expectLater(repository.load(tradeCompanyId:trade,acceptance:false),throwsA(anything));expect(repository.verify,throwsStateError);}
    expect(calls,hasLength(1));expect(repository.isManagedFor(company),isTrue);expect(repository.isManagedFor(trade),isFalse);
   }finally{await repository?.dispose();scope?.dispose();await client.dispose();}
  });
 }
}
