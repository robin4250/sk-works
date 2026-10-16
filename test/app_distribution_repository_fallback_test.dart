import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/referrals/app_referral_repository.dart';

void main() {
  for (final code in ['42501','PGRST301','PGRST000']) {
    test('distribution $code failure does not fall back', () async {
      final calls=<String>[];
      final client=SupabaseClient('https://fixture.example.com','fixture-key',
        httpClient:MockClient((request) async {
          calls.add(request.url.path);
          return http.Response(jsonEncode({'code':code,'message':'blocked'}),403,
            headers:{'content-type':'application/json'});
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
            headers:{'content-type':'application/json'});
        }
        return http.Response(jsonEncode({'can_invite':true}),200,
          headers:{'content-type':'application/json'});
      }));
    expect((await AppReferralRepository(client).load())['can_invite'],true);
    expect(calls,['/rest/v1/rpc/app_distribution_snapshot','/rest/v1/rpc/app_referral_snapshot']);
    await client.dispose();
  });
  test('new channel flag save retains freshly read server legacy URL', () async {
    Map<String,dynamic>? saved;
    final client=SupabaseClient('https://fixture.example.com','fixture-key',
      httpClient:MockClient((request) async {
        if(request.url.path.endsWith('app_distribution_snapshot')) {
          return http.Response(jsonEncode({
            'distribution_channels':[], 'distribution_url':'https://testflight.apple.com/join/CURRENT',
          }),200,headers:{'content-type':'application/json'});
        }
        saved=jsonDecode(request.body) as Map<String,dynamic>;
        return http.Response('{}',200,headers:{'content-type':'application/json'});
      }));
    await AppReferralRepository(client).saveSettingsPreservingDistributionUrl(
      enabled:true,publicEnabled:false,notifyMaster:false,url:'https://testflight.apple.com/join/STALE');
    expect(saved?['p_distribution_url'],'https://testflight.apple.com/join/CURRENT');
    expect(saved?['p_public_enabled'],false);
    await client.dispose();
  });
}
