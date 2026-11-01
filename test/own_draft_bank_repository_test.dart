import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/payroll/own_draft_bank_repository.dart';
import 'package:sk_works/features/payroll/own_draft_bank_admission.dart';
import 'package:sk_works/features/payroll/payroll_statement_repository.dart';
import 'own_bank_account_repository_test.dart' as auth_fixture;
import 'own_draft_bank_admission_test.dart' as fixture;
void main(){
 test('actual SDK shape uses captured bearer/SID and no companyworker args; unavailable is not absent',()async{
  final client=SupabaseClient('https://synthetic.invalid','synthetic',authOptions:const AuthClientOptions(autoRefreshToken:false),httpClient:MockClient((r)async{
   expect(r.url.path,'/rest/v1/rpc/personal_payroll_own_draft_bank_v1');
   expect(jsonDecode(r.body),{'p_statement_id':fixture.id,'p_expected_statement_revision':1,'p_expected_session':fixture.sid});
   final raw={...fixture.response('unavailable'),'actor_id':auth_fixture.actor};
   return http.Response(jsonEncode(raw),200,headers:{'content-type':'application/json'},request:r);
  }));
  await client.auth.setInitialSession(jsonEncode(auth_fixture.session(fixture.sid)));
  final gateway=OwnDraftBankRepository.forClient(client);addTearDown(()async{await gateway.close();await client.dispose();});
  final value=await gateway.read(asOwnDraftStatement(fixture.row()));expect(value.state,OwnDraftBankState.unavailable);expect(value.permits(fixture.id,1),false);
 });
 test('held SDK response after SID change discarded and bank never admitted',()async{
  final entered=Completer<void>(),release=Completer<void>();
  final client=SupabaseClient('https://synthetic.invalid','synthetic',authOptions:const AuthClientOptions(autoRefreshToken:false),httpClient:MockClient((r)async{entered.complete();await release.future;return http.Response(jsonEncode({...fixture.response('confirmed_absent'),'actor_id':auth_fixture.actor}),200,headers:{'content-type':'application/json'},request:r);}));
  await client.auth.setInitialSession(jsonEncode(auth_fixture.session(fixture.sid)));
  final gateway=OwnDraftBankRepository.forClient(client);addTearDown(()async{await gateway.close();await client.dispose();});
  final result=gateway.read(asOwnDraftStatement(fixture.row()));final rejected=expectLater(result,throwsStateError);await entered.future;
  await client.auth.setInitialSession(jsonEncode(auth_fixture.session('20000000-0000-4000-8000-000000000099')));release.complete();await rejected;
 });
}
