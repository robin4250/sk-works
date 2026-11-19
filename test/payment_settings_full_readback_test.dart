import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/payroll/payment_certificate_repository.dart';
import 'package:sk_works/domain/rate_formula_settings.dart';

void main() {
 for(final mutation in ['none','allowance_name','allowance_amount','allowance_missing','tax','welfare','hourly','formula','duplicate']) {
  test('payment setting full readback: $mutation', () async {
   var saves=0,reads=0;
   final value=PartnerPaymentSetting(partnerCompanyId:'synthetic-partner',partnerCompanyName:'Synthetic',dailyRateYen:20000,overtimeHourRateYen:2000,earlyHourRateYen:0,nightHourRateYen:0,
    formulas:const RateFormulaSettings(hourlyBase:true),hourlyBaseRateYen:2500,allowances:const [PaymentAllowanceSetting(name:'  交通費  ',amountYen:1000)],welfareRate:3,taxRate:10);
   final wire=MockClient((request)async {
    if(request.url.path.endsWith('/save_partner_payment_setting')) {
     saves++;final body=jsonDecode(request.body) as Map;expect(body['p_allowances'],[{'name':'  交通費  ','amount_yen':1000}]);
     return http.Response('',204,request:request);
    }
    expect(request.url.path.endsWith('/partner_payment_settings_workspace'),isTrue);reads++;
    final formula=Map<String,dynamic>.from(value.formulas.toMap(hourlyRateYen:value.hourlyBaseRateYen));
    var allowances=<Map<String,dynamic>>[{'name':'  交通費  ','amount_yen':1000}];
    if(mutation=='allowance_name')allowances[0]['name']='別手当';
    if(mutation=='allowance_amount')allowances[0]['amount_yen']=999;
    if(mutation=='allowance_missing')allowances=[];
    if(mutation=='hourly')formula['hourly_rate_yen']=2499;
    if(mutation=='formula')formula['overtime_multiplier']=1.5;
    final row={'partner_company_id':value.partnerCompanyId,'partner_company_name':'Synthetic','daily_rate_yen':20000,'overtime_hour_rate_yen':2000,'early_hour_rate_yen':0,'night_hour_rate_yen':0,
     'rate_formula':formula,'allowances':allowances,'welfare_rate':mutation=='welfare'?2:3,'tax_rate':mutation=='tax'?8:10};
    return http.Response(jsonEncode([row,if(mutation=='duplicate')row]),200,headers:{'content-type':'application/json'},request:request);
   });
   final client=SupabaseClient('https://fixture.invalid','synthetic',httpClient:wire,authOptions:const AuthClientOptions(autoRefreshToken:false));
   try {
    final call=PaymentCertificateRepository.forTesting(client).saveSetting(value);
    if(mutation=='none'){await call;}else{await expectLater(call,throwsStateError);}
    expect(saves,1);expect(reads,1);
   }finally{await client.dispose();}
  });
 }
}
