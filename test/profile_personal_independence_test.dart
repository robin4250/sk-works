import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/profile/profile_repository.dart';
import 'own_bank_account_repository_test.dart' as fixture;

void main() {
 test('company read refusal does not hide own basic profile or invent company membership', () async {
  final paths=<String>[];
  final client=SupabaseClient('https://personal-fixture.invalid','synthetic-public',
   authOptions:const AuthClientOptions(autoRefreshToken:false),httpClient:MockClient((r) async {
    final path=r.url.path.split('/').last;paths.add(path);
    if(path=='company_members') return http.Response(jsonEncode({'code':'42501','message':'synthetic'}),403,headers:{'content-type':'application/json'},request:r);
    final value=path=='user_profiles'?[{'display_name':'Synthetic Own','phone':'','avatar_storage_path':null}]:path=='ensure_personal_sko_id'?'SKO-SYNTHETIC':throw StateError('Unexpected endpoint');
    return http.Response(jsonEncode(value),200,headers:{'content-type':'application/json'},request:r);
   }));
  await client.auth.setInitialSession(jsonEncode(fixture.session('personal-sid')));
  final value=await ProfileRepository.forClient(client).load();
  expect(value.displayName,'Synthetic Own');expect(value.companyAvailable,isFalse);
  expect(value.companyId,isEmpty);expect(value.companyName,isEmpty);
  expect(paths,contains('user_profiles'));expect(paths,contains('ensure_personal_sko_id'));
  await client.dispose();
 });
 test('held personal response after SID switch never becomes old profile', () async {
  final held=Completer<void>();final entered=Completer<void>();
  final client=SupabaseClient('https://personal-fixture.invalid','synthetic-public',
   authOptions:const AuthClientOptions(autoRefreshToken:false),httpClient:MockClient((r) async {
    final path=r.url.path.split('/').last;
    if(path=='company_members') return http.Response('[]',200,headers:{'content-type':'application/json'},request:r);
    if(path=='user_profiles'){entered.complete();await held.future;return http.Response('[{"display_name":"Old Synthetic","phone":""}]',200,headers:{'content-type':'application/json'},request:r);}
    throw StateError('Unexpected endpoint');
   }));
  await client.auth.setInitialSession(jsonEncode(fixture.session('sid-before')));
  final pending=ProfileRepository.forClient(client).load();
  final refused=expectLater(pending,throwsStateError);
  await entered.future;
  await client.auth.setInitialSession(jsonEncode(fixture.session('sid-after')));
  held.complete();await refused;await client.dispose();
 });
}
