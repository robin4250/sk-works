import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/chat/chat_cloud_page.dart';
import 'package:sk_works/features/chat/chat_cloud_repository.dart';
import 'package:sk_works/features/chat/chat_list_widgets.dart';
import 'package:sk_works/features/chat/line_joined_groups_page.dart';
import 'package:sk_works/features/help/menu_help_catalog.dart';
import 'package:sk_works/international/languages/en/english_language_pack.dart';

class _RealHttp extends HttpOverrides {}

const actor = '11111111-1111-4111-8111-111111111111';
const groupId = '44444444-4444-4444-8444-444444444444';
const oldAt = '2026-10-13T10:03:19Z';
const newAt = '2026-10-13T10:04:00Z';

class _Repository implements ChatCloudRepository {
  _Repository(this.delegate);
  final ChatCloudRepository delegate;
  final messages = StreamController<List<Map<String, dynamic>>>.broadcast();
  final rows = List<Map<String, dynamic>>.generate(
    200,
    (index) => {
      'id': 'message-$index',
      'body': index == 199 ? 'Previous latest' : 'Older $index',
      'sent_at': DateTime.utc(
        2026,
        10,
        13,
        10,
      ).add(Duration(seconds: index)).toIso8601String(),
      'sender_user_id': null,
      'sender_display_name': 'LINE sender',
      'origin': 'line',
    },
  );
  int createCalls = 0;
  @override
  String? get currentUserId => actor;
  @override
  Future<({String companyId, String role})> membership() async =>
      (companyId: 'company', role: 'owner');
  @override
  Future<bool> canManagePartnerChat() async => false;
  @override
  Future<List<Map<String, dynamic>>> loadGroups() async => [
    {
      'id': groupId,
      'name': 'Existing SKO group',
      'display_name': 'Existing SKO group',
      'group_type': 'company',
      'participants_only': true,
      'can_edit_group_photo': true,
      'last_activity_at': oldAt,
    },
  ];
  @override
  Future<List<String>> prioritizedSiteGroupIds() async => [];
  @override
  Future<Set<String>> loadBlockedUserIds() async => {};
  @override
  Future<Map<String, dynamic>> loadFriendWorkspace() async => {};
  @override
  Future<List<Map<String, dynamic>>> loadPendingGroupInvites() async => [];
  @override
  Future<Map<String, ChatConversationSummary>> loadConversationSummaries(
    Map<String, DateTime> lastReadByGroup,
  ) => delegate.loadConversationSummaries(lastReadByGroup);
  @override
  Stream<List<Map<String, dynamic>>> watchMessages(String id) {
    expect(id, groupId);
    Future.microtask(() => messages.add(List.of(rows)));
    return messages.stream;
  }

  @override
  Future<String> createCustomGroup(String name) async {
    createCalls++;
    throw StateError('Existing group must not be recreated');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected operation: ${invocation.memberName}');
}

Future<void> advance(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('existing-group LINE help matches both UI entries and keeps English guidance', () {
    for (final key in ['chat', 'line_talk']) {
      final item = MenuHelpCatalog.items.firstWhere((item) => item.key == key);
      expect(item.details, contains('通常グループを先に作成'));
      expect(item.details, contains('トーク機能（︙）'));
      expect(item.details, contains('グループ設定'));
      expect(item.details, contains('グループ名・写真・メンバーはそのまま'));
      expect(
        englishLanguagePack.strings[item.details],
        contains('existing group'),
      );
    }
  });

  testWidgets(
    'real HTTP latest summary survives metadata refresh, history scrolling and list return',
    (tester) async => HttpOverrides.runWithHttpOverrides(() async {
      SharedPreferences.setMockInitialValues({});
      var newest = {
        'id': 'message-199',
        'body': 'Previous latest',
        'sent_at': oldAt,
      };
      var latestRequests = 0;
      var holdLatest = false;
      Completer<void>? latestGate;
      final server = (await tester.runAsync(
        () => HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      ))!;
      server.listen((request) async {
        Object data;
        if (request.uri.path == '/auth/v1/token') {
          String encode(Object value) => base64Url
              .encode(utf8.encode(jsonEncode(value)))
              .replaceAll('=', '');
          data = {
            'access_token':
                '${encode({'alg': 'HS256'})}.${encode({'sub': actor, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.fixture',
            'refresh_token': 'fixture',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {
              'id': actor,
              'aud': 'authenticated',
              'role': 'authenticated',
              'email': 'fixture@example.test',
              'app_metadata': {},
              'user_metadata': {},
              'created_at': '2026-01-01T00:00:00Z',
            },
          };
        } else if (request.uri.path.endsWith('/chat_block_list')) {
          data = [];
        } else {
          expect(request.uri.path, '/rest/v1/chat_messages');
          expect(
            request.uri.queryParameters['communication_group_id'],
            'eq.$groupId',
          );
          if (request.uri.queryParameters['limit'] == '1') {
            expect(
              request.uri.queryParameters['order'],
              'sent_at.desc,id.desc',
            );
            latestRequests++;
            if (holdLatest) await latestGate!.future;
            data = [newest];
          } else {
            final after = DateTime.parse(
              request.uri.queryParameters['sent_at']!.substring(3),
            );
            data = DateTime.parse(newest['sent_at']!).isAfter(after)
                ? [
                    {...newest, 'sender_user_id': null},
                  ]
                : [];
          }
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(data));
        await request.response.close();
      });
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'fixture',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final repository = _Repository(ChatCloudRepository.forTesting(client));
      try {
        await tester.runAsync(
          () => client.auth.signInWithPassword(
            email: 'fixture@example.test',
            password: 'fixture',
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: ChatCloudPage(
              showGroupsInitially: true,
              repository: repository,
            ),
          ),
        );
        await advance(tester);
        expect(
          tester
              .widget<ChatConversationTile>(find.byType(ChatConversationTile))
              .preview,
          'Previous latest',
        );
        await tester.tap(find.text('Existing SKO group'));
        await advance(tester);
        // Stay away from the newest post: this must refresh the list preview
        // without marking an unseen incoming post as read.
        final scrolling = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        scrolling.position.jumpTo(600);
        await tester.pump();
        final requestsBefore = latestRequests;
        newest = {
          'id': 'message-new',
          'body': 'Newest LINE post',
          'sent_at': newAt,
        };
        repository.rows.add({
          ...newest,
          'sender_user_id': null,
          'sender_display_name': 'LINE sender',
          'origin': 'line',
        });
        repository.messages.add(List.of(repository.rows));
        await advance(tester);
        expect(latestRequests, greaterThan(requestsBefore));
        final preferences = await tester.runAsync(
          SharedPreferences.getInstance,
        );
        expect(
          DateTime.parse(
            preferences!.getString(
              'sko_chat_last_read_v2_$actor/company/$groupId',
            )!,
          ).toUtc(),
          DateTime.parse(oldAt).toUtc(),
        );
        // Existing edge gesture returns to the same group's list.
        final gesture = await tester.startGesture(const Offset(12, 200));
        await gesture.moveBy(const Offset(90, 0));
        await gesture.up();
        await advance(tester);
        final tile = tester.widget<ChatConversationTile>(
          find.byType(ChatConversationTile),
        );
        expect(tile.preview, 'Newest LINE post');
        expect(tile.unreadCount, 1);
        expect(repository.createCalls, 0);
        // Metadata reload must not erase a successfully fetched preview while
        // the fresh HTTP summary is still in flight.
        holdLatest = true;
        latestGate = Completer<void>();
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await advance(tester);
        expect(
          tester
              .widget<ChatConversationTile>(find.byType(ChatConversationTile))
              .preview,
          'Newest LINE post',
        );
        latestGate.complete();
        await advance(tester);
      } finally {
        if (latestGate != null && !latestGate.isCompleted)
          latestGate.complete();
        await tester.pumpWidget(const SizedBox());
        await repository.messages.close();
        await tester.runAsync(() => client.dispose());
        await tester.runAsync(() => server.close(force: true));
      }
    }, _RealHttp()),
  );

  testWidgets(
    'existing group exposes LINE add from menu and settings without creation',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      // No backend is used: this test only follows the existing target-group route.
      final client = SupabaseClient(
        'https://fixture.invalid',
        'fixture',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final repository = _Repository(ChatCloudRepository.forTesting(client));
      await tester.pumpWidget(
        MaterialApp(
          home: ChatCloudPage(
            showGroupsInitially: true,
            repository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Existing SKO group'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('トーク機能'));
      await tester.pumpAndSettle();
      expect(find.text('LINEトークを追加'), findsOneWidget);
      await tester.tap(find.text('グループ設定'));
      await tester.pumpAndSettle();
      expect(find.text('LINEトークを追加'), findsOneWidget);
      await tester.tap(find.text('LINEトークを追加'));
      await tester.pumpAndSettle();
      final page = tester.widget<LineJoinedGroupsPage>(
        find.byType(LineJoinedGroupsPage),
      );
      expect(page.targetGroupId, groupId);
      expect(page.selectOnly, false);
      expect(repository.createCalls, 0);
      await tester.pumpWidget(const SizedBox());
      await repository.messages.close();
      await client.dispose();
    },
  );
}
