import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/chat/chat_cloud_repository.dart';

class _RealHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const actor = '11111111-1111-4111-8111-111111111111';
  const other = '22222222-2222-4222-8222-222222222222';
  const peer = '33333333-3333-4333-8333-333333333333';

  for (final scenario in ['removed', 'restricted', 'photo changed', 'actor ABA', 'API unavailable']) {
    test('public friend hydration rejects stale data: $scenario', () =>
      HttpOverrides.runWithHttpOverrides(() async {
        final entered = Completer<void>();
        final release = Completer<void>();
        var tokenActor = actor;
        var workspaceCalls = 0;
        var profileCalls = 0;
        var signedCalls = 0;
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
          Object data;
          if (request.uri.path == '/auth/v1/token') {
            String encode(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
            data = {
              'access_token': '${encode({'alg': 'HS256'})}.${encode({'sub': tokenActor, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.fixture',
              'refresh_token': 'fixture', 'token_type': 'bearer', 'expires_in': 3600,
              'user': {'id': tokenActor, 'aud': 'authenticated', 'role': 'authenticated',
                'email': 'fixture@example.test', 'app_metadata': {}, 'user_metadata': {},
                'created_at': '2026-01-01T00:00:00Z'},
            };
          } else if (request.uri.path.endsWith('/sko_friend_workspace')) {
            workspaceCalls++;
            data = {'friends': workspaceCalls > 1 && scenario == 'removed' ? [] : [
              {'user_id': peer, 'display_name': '公開名', 'sko_id': 'SKO-PEER'},
            ]};
          } else if (request.uri.path.endsWith('/sko_friend_public_profiles')) {
            profileCalls++;
            if (profileCalls == 1) {
              entered.complete();
              await release.future;
            }
            if (scenario == 'API unavailable') {
              request.response.statusCode = 404;
              data = {'code': 'PGRST202', 'message': 'not deployed'};
            } else {
              data = profileCalls > 1 && scenario == 'restricted' ? [] : [
                {'user_id': peer, 'display_name': '公開名', 'company_name': profileCalls > 1 ? '最新公開会社' : '古い公開会社',
                  'avatar_storage_path': '$peer/${profileCalls > 1 && scenario == 'photo changed' ? 'new' : 'old'}.png',
                  'address': '非公開住所は採用不可'},
              ];
            }
          } else if (request.uri.path.contains('/storage/v1/object/sign/')) {
            signedCalls++;
            final payload = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
            expect(payload['expiresIn'], 60);
            data = {'signedURL': '/object/sign/profile-photos/$peer/old.png?token=fixture'};
          } else {
            fail('Unexpected private-data request: ${request.uri.path}');
          }
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(data));
          await request.response.close();
        });
        final client = SupabaseClient('http://127.0.0.1:${server.port}', 'fixture',
          authOptions: const AuthClientOptions(autoRefreshToken: false));
        try {
          await client.auth.signInWithPassword(email: 'fixture@example.test', password: 'fixture');
          final pending = ChatCloudRepository.forTesting(client).loadFriendWorkspace();
          await entered.future;
          if (scenario == 'actor ABA') {
            tokenActor = other;
            await client.auth.signInWithPassword(email: 'fixture@example.test', password: 'fixture');
            tokenActor = actor;
            await client.auth.signInWithPassword(email: 'fixture@example.test', password: 'fixture');
          }
          release.complete();
          final result = await pending;
          if (scenario == 'actor ABA') {
            expect(result, isEmpty);
            expect(signedCalls, 0);
          } else {
            final friends = result['friends'] as List;
            if (scenario == 'removed') {
              expect(friends, isEmpty);
            } else {
              final friend = friends.single as Map;
              expect(friend.containsKey('address'), isFalse);
              if (scenario == 'restricted' || scenario == 'API unavailable') {
                expect(friend['public_profile_loaded'] == true, isFalse);
                expect(friend['avatar_url'], isNull);
                expect(friend['company_name'], isNull);
              } else {
                expect(friend['company_name'], '最新公開会社');
                expect(friend['avatar_url'], isNull);
              }
            }
          }
        } finally {
          if (!release.isCompleted) {
            release.complete();
          }
          await client.dispose();
          await server.close(force: true);
        }
      }, _RealHttp()));
  }
}
