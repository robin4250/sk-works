import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/invoices/invoice_settings_repository.dart';
void main(){
 for(final mismatch in ['none','tax','welfare']){
  test('invoice rate save readback: $mismatch',()async{
   var saves=0,branding=0,companyReads=0;
   final wire=MockClient((request)async{
    Object? body;
    final path=request.url.path;
    if(path.endsWith('/company_members')){body=[{'company_id':'synthetic-company'}];}
    else if(path.endsWith('/current_feature_permissions')){body={'can_manage_invoices':true};}
    else if(path.endsWith('/save_invoice_settings_v2')){
     saves++;final sent=jsonDecode(request.body) as Map;expect(sent['p_tax_rate'],10);expect(sent['p_welfare_rate'],3);
     return http.Response('',204,request:request);
    }else if(path.endsWith('/save_invoice_branding')){branding++;return http.Response('',204,request:request);}
    else if(path.endsWith('/companies')){companyReads++;body=[{'name':'Synthetic','tax_rate':mismatch=='tax'?8:10,'default_welfare_rate':mismatch=='welfare'?2:3}];}
    else {expect(path.endsWith('/company_private_billing_settings'),isTrue);body=<Object>[];}
    return http.Response(jsonEncode(body),200,headers:{'content-type':'application/json'},request:request);
   });
   final client=SupabaseClient('https://fixture.invalid','synthetic',httpClient:wire,authOptions:const AuthClientOptions(autoRefreshToken:false));
   try{
    String part(Object value)=>base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=','');
    await client.auth.setInitialSession(jsonEncode({'access_token':'${part({'alg':'HS256'})}.${part({'sub':'synthetic-actor','exp':DateTime.now().millisecondsSinceEpoch~/1000+3600})}.synthetic','refresh_token':'synthetic','expires_in':3600,'token_type':'bearer','user':{'id':'synthetic-actor','aud':'authenticated','created_at':'2026-01-01T00:00:00Z'}}));
    const value=InvoiceSettingsData(companyName:'Synthetic',taxRate:10,welfareRate:3,templateTitle:'請求書',footerNote:'',bankName:'',bankBranch:'',bankAccountType:'普通',bankAccountNumber:'',bankAccountHolder:'');
    final call=InvoiceSettingsRepository.forTesting(client).save(value);
    if(mismatch=='none'){await call;}else{await expectLater(call,throwsStateError);}
    expect(saves,1);expect(branding,1);expect(companyReads,1);
   }finally{await client.dispose();}
  });
 }
}
