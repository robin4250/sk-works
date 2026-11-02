// ignore_for_file: invalid_use_of_internal_member
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/payroll/own_draft_bank_repository.dart';
import 'package:sk_works/features/payroll/own_draft_bank_diagnostic.dart';
import 'package:sk_works/features/payroll/own_draft_bank_admission.dart';
import 'package:sk_works/features/payroll/payroll_statement_repository.dart';
import 'own_bank_account_repository_test.dart' as auth;
import 'own_draft_bank_admission_test.dart' as fixture;
import 'support/own_draft_bank_before_replay.dart' as before;

class Fixture {
 int calls=0;
 Completer<void>? entered,release;
 late final SupabaseClient client=SupabaseClient('https://own-bank-replay.invalid','public-fixture',authOptions:const AuthClientOptions(autoRefreshToken:false),httpClient:MockClient((r)async{
  expect(r.url.host,'own-bank-replay.invalid');expect(r.url.path,'/rest/v1/rpc/personal_payroll_own_draft_bank_v1');
  expect(r.headers['Authorization'],'Bearer ${client.auth.currentSession!.accessToken}');
  calls++;entered?.complete();if(release!=null)await release!.future;
  // Synthetic contract fixture only; never print raw response or bank values.
  return http.Response(jsonEncode({...fixture.response('confirmed_absent'),'actor_id':auth.actor}),200,headers:{'content-type':'application/json'},request:r);
 }));
 Future<void> start(AuthChangeEvent event)async {
  await client.auth.setInitialSession(jsonEncode(auth.session(fixture.sid)));
  client.auth.notifyAllSubscribers(event,broadcast:false);
 }
}
void main(){
 test('original source rejects a cached signedIn replay before any bank RPC',()async{
  final f=Fixture();await f.start(AuthChangeEvent.signedIn);
  final g=before.BeforeReplayOwnDraftBankRepository.forClient(f.client);addTearDown(()async{await g.close();await f.client.dispose();});
  await expectLater(g.read(asOwnDraftStatement(fixture.row())),throwsStateError);expect(f.calls,0);
 });
 for(final event in [AuthChangeEvent.initialSession,AuthChangeEvent.signedIn,AuthChangeEvent.tokenRefreshed]){
  test('exact queued $event replay permits captured-SID/bearer read',()async{
   final f=Fixture();await f.start(event);final captured=f.client.auth.currentSession;
   final g=OwnDraftBankRepository.forClient(f.client);addTearDown(()async{await g.close();await f.client.dispose();});
   final value=await g.read(asOwnDraftStatement(fixture.row()));
   expect(value.state,OwnDraftBankState.confirmedAbsent);expect(value.permits(fixture.id,1),true);expect(f.calls,1);expect(identical(captured,f.client.auth.currentSession),true);
  });
 }
 test('later same-object token refresh permanently retires old lease without second RPC',()async{
  final f=Fixture();await f.start(AuthChangeEvent.signedIn);final g=OwnDraftBankRepository.forClient(f.client);addTearDown(()async{await g.close();await f.client.dispose();});
  final value=await g.read(asOwnDraftStatement(fixture.row()));expect(value.permits(fixture.id,1),true);
  f.client.auth.notifyAllSubscribers(AuthChangeEvent.tokenRefreshed,broadcast:false);await Future<void>.delayed(Duration.zero);
  expect(value.permits(fixture.id,1),false);
  await expectLater(g.read(asOwnDraftStatement(fixture.row())),throwsA(isA<OwnDraftBankReadFailure>().having((e)=>e.diagnostic.safeMetadata,'finite metadata',{'stage':'session','issue':'authenticationEvent'})));
  expect(f.calls,1);
 });
 test('session replacement before queued replay is denied, not adopted',()async{
  final f=Fixture();await f.start(AuthChangeEvent.signedIn);final g=OwnDraftBankRepository.forClient(f.client);addTearDown(()async{await g.close();await f.client.dispose();});
  await f.client.auth.setInitialSession(jsonEncode(auth.session(fixture.sid)));
  await expectLater(g.read(asOwnDraftStatement(fixture.row())),throwsStateError);expect(f.calls,0);
 });
 test('held response after SID change never grants bank admission',()async{
  final f=Fixture()..entered=Completer<void>()..release=Completer<void>();await f.start(AuthChangeEvent.signedIn);
  final g=OwnDraftBankRepository.forClient(f.client);addTearDown(()async{await g.close();await f.client.dispose();});
  final result=g.read(asOwnDraftStatement(fixture.row()));final rejected=expectLater(result,throwsStateError);await f.entered!.future;
  await f.client.auth.setInitialSession(jsonEncode(auth.session('20000000-0000-4000-8000-000000000099')));f.release!.complete();await rejected;expect(g.isCurrent,false);
 });
}
