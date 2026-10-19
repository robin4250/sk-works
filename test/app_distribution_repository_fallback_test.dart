// SDK transport fixtures use the http version already pinned in pubspec.lock.
// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/referrals/app_referral_repository.dart';

void main() {
  test('channel flags use one atomic call without a legacy URL', () async {
    final calls = <String>[];
    Map<String,dynamic>? saved;
    final client = SupabaseClient('https://fixture.example.com', 'fixture-key',
      httpClient: MockClient((request) async {
        calls.add(request.url.path);
        saved = jsonDecode(request.body) as Map<String,dynamic>;
        return http.Response('{}', 200, request: request,
          headers: {'content-type': 'application/json'});
      }));
    await AppReferralRepository(client).saveSettingsPreservingDistributionUrl(
      enabled: true, publicEnabled: false, notifyMaster: false);
    expect(calls, ['/rest/v1/rpc/app_referral_save_flags']);
    expect(saved, {'p_enabled': true, 'p_public_enabled': false, 'p_notify_master': false});
    await client.dispose();
  });
  for (final code in ['PGRST202', '42501', 'PGRST301']) {
    test('atomic flag $code failure never rewrites the legacy URL', () async {
      final calls = <String>[];
      final client = SupabaseClient('https://fixture.example.com', 'fixture-key',
        httpClient: MockClient((request) async {
          calls.add(request.url.path);
          return http.Response(jsonEncode({'code': code, 'message': 'unavailable'}), 403,
            request: request, headers: {'content-type': 'application/json'});
        }));
      await expectLater(AppReferralRepository(client).saveSettingsPreservingDistributionUrl(
        enabled: true, publicEnabled: false, notifyMaster: false),
        throwsA(isA<PostgrestException>()));
      expect(calls, ['/rest/v1/rpc/app_referral_save_flags']);
      await client.dispose();
    });
  }
  for (final code in ['42501','PGRST301','PGRST000']) {
    test('distribution $code failure does not fall back', () async {
      final calls=<String>[];
      final client=SupabaseClient('https://fixture.example.com','fixture-key',
        httpClient:MockClient((request) async {
          calls.add(request.url.path);
          return http.Response(jsonEncode({'code':code,'message':'blocked'}),403,
            request:request,headers:{'content-type':'application/json'});
        }));
      await expectLater(AppReferralRepository(client).load(),throwsA(isA<PostgrestException>()));
      expect(calls,['/rest/v1/rpc/app_distribution_snapshot']);
      await client.dispose();
    });
  }
  test('missing channel RPC alone loads authorized legacy snapshot', () async {
    final calls=<String>[];
    final client=SupabaseClient('https://fixture.example.com','fixture-key',
      httpClient:MockClient((request) async {
        calls.add(request.url.path);
        if(request.url.path.endsWith('app_distribution_snapshot')) {
          return http.Response(jsonEncode({'code':'PGRST202','message':'missing'}),404,
            request:request,headers:{'content-type':'application/json'});
        }
        return http.Response(jsonEncode({'can_invite':true}),200,
          request:request,headers:{'content-type':'application/json'});
      }));
    expect((await AppReferralRepository(client).load())['can_invite'],true);
    expect(calls,['/rest/v1/rpc/app_distribution_snapshot','/rest/v1/rpc/app_referral_snapshot']);
    await client.dispose();
  });
}

