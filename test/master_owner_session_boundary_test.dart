// ignore_for_file: invalid_use_of_internal_member
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/settings/master_owner_access.dart';
import 'package:sk_works/features/settings/master_protected_page.dart';
import 'package:sk_works/features/settings/settings_page.dart';
import 'package:sk_works/features/chat/line_master_workspace_page.dart';
import 'support/line_test_app.dart';

const other = '81000000-0000-0000-0000-000000000002';
const sid = '81000000-0000-0000-0000-000000000003';
Map<String, dynamic> session(String actor, String nonce) {
  String part(Object v) =>
      base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
  return {
    'access_token':
        '${part({'alg': 'HS256'})}.${part({'sub': actor, 'role': 'authenticated', 'session_id': sid, 'nonce': nonce, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.fixture',
    'refresh_token': 'fixture-$nonce',
    'token_type': 'bearer',
    'expires_in': 3600,
    'user': {
      'id': actor,
      'aud': 'authenticated',
      'created_at': '2026-10-16T00:00:00Z',
      'app_metadata': <String, dynamic>{},
      'user_metadata': <String, dynamic>{},
    },
  };
}

late SupabaseClient client;
Completer<void>? masterWait;
Completer<void>? masterReached;
int masterCalls = 0;
final bearers = <String>[];
Future<void> login(String actor, String nonce) async {
  await client.auth.setInitialSession(jsonEncode(session(actor, nonce)));
}

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 15; i++) {
    await t.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    client = SupabaseClient('https://master-owner-fixture.invalid', 'public-fixture',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((r) async {
        expect(r.url.host, 'master-owner-fixture.invalid');
        final name = r.url.path.split('/').last;
        Object result;
        if (name == 'current_master_admin_status') {
          masterCalls++;
          bearers.add(r.headers['Authorization'] ?? '');
          masterReached?.complete();
          masterReached = null;
          final wait = masterWait;
          if (wait != null) await wait.future;
          result = {
            'is_master_admin': true,
          }; // even a permissive server never grants a non-owner client.
        } else if (name == 'company_members') {
          result = [
            {
              'company_id': '81000000-0000-0000-0000-000000000004',
              'role': 'owner',
            },
          ];
        } else if (name == 'companies') {
          result = [
            {'id': '81000000-0000-0000-0000-000000000004'},
          ];
        } else {
          result = <Object>[];
        }
        return http.Response(
          jsonEncode(result),
          200,
          headers: {'content-type': 'application/json'},
          request: r,
        );
      }),
    );

  });
  setUp(() {
    masterWait = null;
    masterReached = null;
    masterCalls = 0;
    bearers.clear();
  });
  tearDownAll(() async {
    await client.dispose();
  });

  testWidgets(
    'owner/nonowner and direct route denial preserve server and UID boundaries',
    (t) async {
      await login(MasterOwnerAccess.ownerId, 'owner');
      expect(await MasterOwnerAccess.check(client), isTrue);
      expect(masterCalls, 1);
      await login(other, 'other');
      expect(await MasterOwnerAccess.check(client), isFalse);
      expect(
        masterCalls,
        1,
        reason: 'non-owner must be rejected before server RPC',
      );
      await t.pumpWidget(
        MaterialApp(
          home: MasterProtectedPage(
            ownerClient: client,
            title: 'fixture',
            dedicatedMode: true,
            child: Scaffold(body: Text('DO-NOT-MOUNT')),
          ),
        ),
      );
      await settle(t);
      expect(find.text('DO-NOT-MOUNT'), findsNothing);
      expect(find.text('Master認証を利用できません。'), findsOneWidget);
      await t.pumpWidget(LineTestApp(home: LineMasterWorkspacePage(client: client, masterCheck: () async => true)));
      await settle(t);
      expect(find.byKey(const ValueKey('line-master-chat')), findsNothing);
      expect(masterCalls, 1, reason: 'callback cannot bypass non-owner pre-RPC denial');
      await t.pumpWidget(const MaterialApp(home: MasterProtectedPage(title: 'unconfigured-default', dedicatedMode: true, child: Text('DEFAULT-MUST-NOT-MOUNT'))));
      await settle(t);
      expect(find.text('DEFAULT-MUST-NOT-MOUNT'), findsNothing);
      expect(find.text('Master認証を利用できません。'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'same UID/SID refresh reevaluates settings and workspace with new captured bearer',
    (t) async {
      await t.binding.setSurfaceSize(const Size(1000, 5000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await login(MasterOwnerAccess.ownerId, 'before-refresh');
      await t.pumpWidget(MaterialApp(home: SettingsPage(client: client)));
      await settle(t);
      expect(find.text('Master 機能設定'), findsOneWidget);
      final oldToken = client.auth.currentSession!.accessToken;
      await login(MasterOwnerAccess.ownerId, 'after-refresh');
      // Emit actual SDK auth notification under the replacement same-UID/SID Session.
      client.auth.notifyAllSubscribers(
        AuthChangeEvent.tokenRefreshed,
        broadcast: false,
      );
      await settle(t);
      expect(find.text('Master 機能設定'), findsOneWidget);
      expect(bearers.last, 'Bearer ${client.auth.currentSession!.accessToken}');
      expect(bearers.last, isNot('Bearer $oldToken'));
      await t.pumpWidget(LineTestApp(home: LineMasterWorkspacePage(client: client)));
      await settle(t);
      expect(find.byKey(const ValueKey('line-master-chat')), findsOneWidget);
      await login(MasterOwnerAccess.ownerId, 'workspace-refresh');
      client.auth.notifyAllSubscribers(
        AuthChangeEvent.tokenRefreshed,
        broadcast: false,
      );
      await settle(t);
      expect(find.byKey(const ValueKey('line-master-chat')), findsOneWidget);
      expect(bearers.last, 'Bearer ${client.auth.currentSession!.accessToken}');
      await t.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'stream error invalidates pending old true in settings and workspace',
    (t) async {
      await login(MasterOwnerAccess.ownerId, 'pending-settings');
      masterWait = Completer<void>();
      masterReached = Completer<void>();
      await t.pumpWidget(MaterialApp(home: SettingsPage(client: client)));
      await settle(t);
      expect(
        masterReached,
        isNull,
        reason: 'held real product status request was reached',
      );
      client.auth.notifyException(StateError('synthetic-auth-stream-error'));
      await t.pump();
      masterWait!.complete();
      masterWait = null;
      await settle(t);
      expect(find.text('Master 機能設定'), findsNothing);
      expect(find.textContaining('ログイン状態を確認できません'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
      await login(MasterOwnerAccess.ownerId, 'pending-workspace');
      masterWait = Completer<void>();
      masterReached = Completer<void>();
      await t.pumpWidget(LineTestApp(home: LineMasterWorkspacePage(client: client)));
      await settle(t);
      expect(masterReached, isNull);
      client.auth.notifyException(StateError('synthetic-auth-stream-error'));
      await t.pump();
      masterWait!.complete();
      masterWait = null;
      await settle(t);
      expect(find.byKey(const ValueKey('line-master-chat')), findsNothing);
      expect(find.textContaining('ログイン状態を確認できません'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
}
