import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sk_works/features/chat/chat_cloud_repository.dart';
import 'package:sk_works/features/chat/chat_friends_page.dart';

class _Repository implements ChatCloudRepository {
  String actor = 'self';
  String peerName = '会話の友達';
  int loads = 0;
  final searchedIds = <String>[];
  @override
  Future<Map<String, dynamic>?> searchFriendBySkoId(String value) async {
    searchedIds.add(value);
    return null;
  }
  final changes = StreamController<String?>.broadcast();
  @override
  String get currentUserId => actor;
  @override
  Stream<String?> watchActorChanges() => changes.stream;
  @override
  Future<Map<String, dynamic>> loadFriendWorkspace() async {
    loads++;
    return {
    'friends': [
      {'user_id': 'old', 'display_name': '古い友達', 'sko_id': 'SKO-OLD', 'created_at': '2026-01-01'},
      {'user_id': 'peer', 'display_name': peerName, 'sko_id': 'SKO-PEER', 'created_at': '2026-02-01'},
    ],
  };
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final systemBack in [false, true]) {
    testWidgets('nested ID search returns to retained chats via ${systemBack ? 'system' : 'screen'} back', (tester) async {
      final repo = _Repository();
      addTearDown(repo.changes.close);
      final chatQuery = TextEditingController(text: '保持する検索');
      addTearDown(chatQuery.dispose);
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
        return Scaffold(body: Column(children: [
          TextField(controller: chatQuery),
          TextButton(onPressed: () {
            final chatRoute = ModalRoute.of(context);
            final navigator = Navigator.of(context);
            var returning = false;
            void returnToChats() {
              if (returning) return;
              returning = true;
              navigator.popUntil((route) => identical(route, chatRoute));
              returning = false;
            }
            navigator.push<void>(MaterialPageRoute(builder: (_) => ChatFriendsPage(
              repository: repo, selectForChat: true, onReturnToChats: returnToChats,
            )));
          }, child: const Text('チャットから友達')),
        ]));
      })));
      await tester.tap(find.text('チャットから友達'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('追加'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ID検索'));
      await tester.pumpAndSettle();
      expect(find.text('SKO-'), findsOneWidget);
      if (systemBack) {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tap(find.byType(BackButton));
      }
      await tester.pumpAndSettle();
      expect(find.text('チャットから友達'), findsOneWidget);
      expect(chatQuery.text, '保持する検索');
      expect(find.byType(ChatFriendsPage), findsNothing);
      expect(Navigator.of(tester.element(find.text('チャットから友達'))).canPop(), isFalse);
    });
  }

  testWidgets('fixed prefix survives clearing and full ID paste searches once', (tester) async {
    final repo = _Repository();
    addTearDown(repo.changes.close);
    await tester.pumpWidget(MaterialApp(home: ChatFriendsPage(repository: repo)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'SKO-ABC123');
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'ABC123');
    await tester.tap(find.byTooltip('検索'));
    await tester.pumpAndSettle();
    expect(repo.searchedIds, ['SKO-ABC123']);
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.byTooltip('検索'));
    await tester.pumpAndSettle();
    expect(repo.searchedIds, ['SKO-ABC123']);
    expect(find.text('SKO-'), findsOneWidget);
  });

  testWidgets('refresh and resume fetch peer updates without reopening', (tester) async {
    final repo = _Repository();
    addTearDown(repo.changes.close);
    await tester.pumpWidget(MaterialApp(home: ChatFriendsPage(repository: repo, selectForChat: true)));
    await tester.pumpAndSettle();
    repo.peerName = '承認後の友達';
    await tester.tap(find.byTooltip('友達一覧を更新'));
    await tester.pumpAndSettle();
    expect(find.text('承認後の友達'), findsOneWidget);
    final before = repo.loads;
    for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    repo.peerName = '復帰後の友達';
    for (final state in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
    expect(repo.loads, greaterThan(before));
    expect(find.text('復帰後の友達'), findsOneWidget);
    repo.actor = 'other';
    repo.changes.add('other');
    await tester.pumpAndSettle();
    final invalidatedLoads = repo.loads;
    await tester.tap(find.byTooltip('友達一覧を更新'));
    await tester.pumpAndSettle();
    expect(repo.loads, invalidatedLoads);
    expect(find.text('復帰後の友達'), findsNothing);
  });

  testWidgets('existing DM priority, profile intent and fixed add help', (tester) async {
    final repo = _Repository();
    addTearDown(repo.changes.close);
    await tester.pumpWidget(MaterialApp(home: ChatFriendsPage(
      repository: repo,
      selectForChat: true,
      existingGroups: const [{'group_type': 'direct', 'direct_other_user_id': 'peer'}],
    )));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('会話の友達')).dy, lessThan(tester.getTopLeft(find.text('古い友達')).dy));
    await tester.enterText(find.byType(TextField), 'SKO-OLD');
    await tester.pump();
    expect(find.text('会話の友達'), findsNothing);
    await tester.enterText(find.byType(TextField), 'not-found');
    await tester.pump();
    expect(find.textContaining('一致する友達はいません'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    await tester.tap(find.text('追加'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('電話番号通知'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ログイン情報を確認できません'), findsOneWidget);
    await tester.tap(find.byTooltip('使い方'));
    await tester.pumpAndSettle();
    expect(find.textContaining('全履歴'), findsOneWidget);
  });

  testWidgets('phone add preserves existing invitation callback and friend source', (tester) async {
    final repo = _Repository();
    addTearDown(repo.changes.close);
    final sources = <String>[];
    await tester.pumpWidget(MaterialApp(home: ChatFriendsPage(
      repository: repo,
      selectForChat: true,
      onPhoneInvitation: (context, source) async { sources.add(source); },
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('追加'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('電話番号通知'));
    await tester.pumpAndSettle();
    expect(sources, ['friend_add']);
    expect(find.textContaining('ログイン情報を確認できません'), findsNothing);
  });

  for (final picker in [false, true]) {
    testWidgets('direct SKO invite opens existing callback from ${picker ? 'chat picker' : 'friend management'}', (tester) async {
      final repo = _Repository();
      addTearDown(repo.changes.close);
      final sources = <String>[];
      final pending = Completer<void>();
      await tester.pumpWidget(MaterialApp(home: ChatFriendsPage(
        repository: repo,
        selectForChat: picker,
        onPhoneInvitation: (context, source) async {
          sources.add(source);
          await pending.future;
        },
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'SKO招待'));
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'SKO招待'));
      await tester.pump();
      expect(sources, ['friend_add']);
      final before = repo.loads;
      pending.complete();
      await tester.pumpAndSettle();
      expect(repo.loads, before + 1);
      repo.actor = 'other';
      repo.changes.add('other');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'SKO招待'));
      await tester.pump();
      expect(sources, ['friend_add']);
    });
  }

  testWidgets('group member picker does not expose app invitation', (tester) async {
    final repo = _Repository();
    addTearDown(repo.changes.close);
    await tester.pumpWidget(MaterialApp(home: ChatFriendsPage(
      repository: repo, selectForGroupInvite: true,
    )));
    await tester.pumpAndSettle();
    expect(find.text('SKO招待'), findsNothing);
  });

  testWidgets('pin keeps row, persists per actor and actor change clears identity', (tester) async {
    final repo = _Repository();
    addTearDown(repo.changes.close);
    await tester.pumpWidget(MaterialApp(home: ChatFriendsPage(repository: repo, selectForChat: true)));
    await tester.pumpAndSettle();
    await tester.drag(find.text('会話の友達'), const Offset(600, 0));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('sko_chat_friend_pinned_self'), ['peer']);
    expect(prefs.getStringList('sko_chat_friend_pinned_other'), isNull);
    expect(find.text('会話の友達'), findsOneWidget);
    repo.actor = 'other';
    repo.changes.add('other');
    await tester.pumpAndSettle();
    expect(find.text('会話の友達'), findsNothing);
    expect(find.textContaining('ログイン情報が変わりました'), findsOneWidget);
  });
}

