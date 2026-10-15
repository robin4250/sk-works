import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sk_works/features/chat/chat_cloud_page.dart';
import 'package:sk_works/features/chat/chat_cloud_repository.dart';

class _Repository implements ChatCloudRepository {
  String actor = 'self';
  int starts = 0;
  final actors = StreamController<String?>.broadcast();
  @override
  String get currentUserId => actor;
  @override
  Stream<String?> watchActorChanges() => actors.stream;
  @override
  Future<({String companyId, String role})> membership() async =>
      (companyId: 'company', role: 'owner');
  @override
  Future<bool> canManagePartnerChat() async => false;
  @override
  Future<List<Map<String, dynamic>>> loadGroups() async => [
    {'id': 'old', 'group_type': 'direct', 'display_name': '古い個別トーク',
     'direct_other_user_id': 'peer', 'last_activity_at': '2026-01-01'},
    {'id': 'new', 'group_type': 'direct', 'display_name': '新しい個別トーク',
     'direct_other_user_id': 'other-peer', 'last_activity_at': '2026-02-01'},
  ];
  @override
  Future<List<String>> prioritizedSiteGroupIds() async => [];
  @override
  Future<Set<String>> loadBlockedUserIds() async => {};
  @override
  Future<Map<String, dynamic>> loadFriendWorkspace() async => {
    'friends': [{'user_id': 'peer', 'display_name': '再開する友達', 'sko_id': 'SKO-PEER'}],
  };
  @override
  Future<List<Map<String, dynamic>>> loadPendingGroupInvites() async => [];
  @override
  Stream<String> watchConversationChanges() => const Stream.empty();
  @override
  Future<Map<String, ChatConversationSummary>> loadConversationSummaries(
    Map<String, DateTime> lastReadByGroup,
  ) async => {};
  @override
  Future<String> startDirectChat(String userId) async {
    expect(userId, 'peer');
    starts++;
    return 'old';
  }
  @override
  Stream<List<Map<String, dynamic>>> watchMessages(String id) => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected operation: ${invocation.memberName}');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<_Repository> open(WidgetTester tester) async {
    final repo = _Repository();
    addTearDown(repo.actors.close);
    await tester.pumpWidget(MaterialApp(home: ChatCloudPage(
      repository: repo, actorChanges: repo.actors.stream,
    )));
    await tester.pumpAndSettle();
    expect(find.text('古い個別トーク'), findsOneWidget);
    return repo;
  }

  Future<void> swipe(WidgetTester tester, String id, double dx) async {
    await tester.drag(find.byKey(ValueKey('chat-list-actions-$id')), Offset(dx, 0));
    await tester.pumpAndSettle();
  }

  testWidgets('DM pin orders the list and mute remains local to the actor', (tester) async {
    await open(tester);
    await swipe(tester, 'old', 600);
    await tester.tap(find.text('上位にピン留め'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('古い個別トーク')).dy,
        lessThan(tester.getTopLeft(find.text('新しい個別トーク')).dy));
    await swipe(tester, 'old', 600);
    await tester.tap(find.text('通知音をOFF'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('sko_chat_pinned_self'), ['old']);
    expect(prefs.getStringList('sko_chat_muted_self'), ['old']);
    expect(prefs.getStringList('sko_chat_muted_other'), isNull);
    expect(find.text('古い個別トーク'), findsOneWidget);
  });

  testWidgets('cancel preserves DM; confirmed removal hides locally and friend reopens same DM', (tester) async {
    final repo = await open(tester);
    await swipe(tester, 'old', -600);
    await tester.tap(find.text('戻る'));
    await tester.pumpAndSettle();
    expect(find.text('古い個別トーク'), findsOneWidget);
    await swipe(tester, 'old', -600);
    expect(find.textContaining('友達関係・メッセージは削除しません'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '削除'));
    await tester.pumpAndSettle();
    expect(find.text('古い個別トーク'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('sko_chat_hidden_self'), ['old']);
    await tester.tap(find.text('友達一覧'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('再開する友達'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('チャットを始める'));
    await tester.pumpAndSettle();
    expect(repo.starts, 1);
    expect(prefs.getStringList('sko_chat_hidden_self'), isEmpty);
    await tester.tap(find.byTooltip('トーク一覧に戻る'));
    await tester.pumpAndSettle();
    expect(find.text('古い個別トーク'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('actor change while confirmation is open cannot hide either account DM', (tester) async {
    final repo = await open(tester);
    await swipe(tester, 'old', -600);
    repo.actor = 'other';
    repo.actors.add('other');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '削除'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('sko_chat_hidden_self'), isNull);
    expect(prefs.getStringList('sko_chat_hidden_other'), isNull);
    expect(find.text('古い個別トーク'), findsOneWidget);
  });

  testWidgets('actor change while pin sheet is open cannot save another account preference', (tester) async {
    final repo = await open(tester);
    await swipe(tester, 'old', 600);
    repo.actor = 'other';
    repo.actors.add('other');
    await tester.pumpAndSettle();
    await tester.tap(find.text('上位にピン留め'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('sko_chat_pinned_self'), isNull);
    expect(prefs.getStringList('sko_chat_pinned_other'), isNull);
  });
}
