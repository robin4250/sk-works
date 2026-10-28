// Runs only while the dedicated CI temporarily restores the exact original
// c9ed8fd4 adapter. The normal full suite skips this old-behavior observation.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/shifts/own_published_shift_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('exact original adapter rejects normal first load after actual SDK replay',() async {
    const actor='10000000-0000-4000-8000-000000000001';
    String part(Object value)=>base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=','');
    final paths=<String>[];
    final client=SupabaseClient('https://shift-baseline.invalid','synthetic-public',
      authOptions:const AuthClientOptions(autoRefreshToken:false),
      httpClient:MockClient((request) async {
        paths.add(request.url.path);
        return http.Response(jsonEncode([{'company_id':'company'}]),200,
          headers:{'content-type':'application/json'},request:request);
      }));
    await client.auth.setInitialSession(jsonEncode({
      'access_token':'${part({'alg':'HS256'})}.${part({'sub':actor,'exp':4102444800})}.synthetic',
      'refresh_token':'synthetic-refresh','token_type':'bearer','expires_in':3600,
      'user':{'id':actor,'aud':'authenticated','created_at':'2026-01-01T00:00:00Z',
        'app_metadata':<String,dynamic>{},'user_metadata':<String,dynamic>{}}}));
    final value=OwnPublishedShiftRepository(client);
    try {
      await expectLater(value.loadContext(),throwsStateError);
      expect(paths,hasLength(1)); expect(paths.single,endsWith('/company_members'));
    } finally { value.dispose(); await client.dispose(); }
  },skip:!const bool.fromEnvironment('SKO_SHIFT_REPLAY_BASELINE'));
}
