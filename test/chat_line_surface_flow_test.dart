import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sk_works/features/chat/chat_cloud_page.dart';
import 'package:sk_works/features/chat/chat_cloud_repository.dart';

class SurfaceRepository implements ChatCloudRepository {
  int writes = 0;
  bool canDeleteGroup = false;
  final deletedGroups = <String>[];
  String? actorId = 'actor';
  bool mapped = true;
  bool failSavedSummary = false;
  bool allUnknown = false;
  Completer<void>? retryGate;
  final dispatches = <String>[];
  final messages = StreamController<List<Map<String, dynamic>>>.broadcast();
  @override
  String? get currentUserId => actorId;
  @override
  Future<({String companyId, String role})> membership() async =>
      (companyId: 'company', role: 'owner');
  @override
  Future<bool> canManagePartnerChat() async => false;
  @override
  Future<List<Map<String, dynamic>>> loadGroups() async => [
    {
      'id': 'line-only',
      'name': 'LINE only',
      'display_name': 'LINE only',
      'group_type': 'company',
      'participants_only': true,
      'can_delete_group': canDeleteGroup,
      'line_origin': mapped ? 'line' : null,
    },
    {
      'id': 'shared',
      'name': 'Shared group',
      'display_name': 'Shared group',
      'group_type': 'company',
      'participants_only': true,
      'line_origin': 'sko',
    },
  ].where((group) => !deletedGroups.contains(group['id'])).toList();
  @override
  Future<void> deleteCustomGroup(String id) async { deletedGroups.add(id); }
  @override
  Future<List<String>> prioritizedSiteGroupIds() async => [];
  @override
  Future<Set<String>> loadBlockedUserIds() async => {};
  @override
  Future<Map<String, dynamic>> loadFriendWorkspace() async => {};
  @override
  Future<List<Map<String, dynamic>>> loadPendingGroupInvites() async => [];
  @override
  Stream<String> watchConversationChanges() => const Stream.empty();
  @override
  Future<Map<String, ChatConversationSummary>> loadConversationSummaries(
    Map<String, DateTime> lastReadByGroup,
  ) async {
    if (failSavedSummary && writes > 0) throw StateError('Summary read failed');
    return {};
  }

  @override
  Stream<List<Map<String, dynamic>>> watchMessages(String groupId) {
    Future.microtask(
      () => messages.add([
        {
          'id': 'old',
          'body': 'Old message',
          'sent_at': '2026-10-13T20:00:00Z',
          'sender_user_id': 'actor',
        },
      ]),
    );
    return messages.stream;
  }

  @override
  Future<String> sendMessage({
    required String groupId,
    required String body,
  }) async {
    writes++;
    return writes == 1 ? 'saved-message' : 'saved-message-$writes';
  }

  @override
  Future<String> dispatchLineMessage(String messageId) async {
    dispatches.add(messageId);
    if (messageId == 'saved-message' &&
        dispatches.where((id) => id == messageId).length > 1) {
      await retryGate?.future;
    }
    return allUnknown || dispatches.length == 1 ? 'unknown' : 'accepted';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected ${invocation.memberName}');
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
}

void main() {
  testWidgets(
    'SKO list hides LINE-only origin but exposes shared canonical group',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final repo = SurfaceRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: ChatCloudPage(repository: repo, showGroupsInitially: true),
        ),
      );
      await settle(tester);
      expect(find.text('LINE only'), findsNothing);
      expect(find.text('Shared group'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      unawaited(repo.messages.close());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'LINE entry opens same canonical composer and retry never reinserts saved post',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final repo = SurfaceRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: ChatCloudPage(repository: repo, initialGroupId: 'line-only'),
        ),
      );
      await settle(tester);
      expect(find.text('Old message'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'New post');
      await tester.tap(find.byTooltip('送信'));
      await settle(tester);
      expect(repo.writes, 1);
      expect(repo.dispatches, ['saved-message']);
      expect(find.text('SKO保存済み・LINE送信未確認'), findsOneWidget);
      await tester.tap(find.text('LINE再試行'));
      await settle(tester);
      expect(repo.writes, 1);
      expect(repo.dispatches, ['saved-message', 'saved-message']);
      expect(find.text('LINE受付済み（配信確認はLINE側で）'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      unawaited(repo.messages.close());
      await tester.pumpAndSettle();
    },
  );
  for (final holdRetry in [false, true]) {
    testWidgets(
      holdRetry
          ? 'a new saved message dispatches while older retry is pending'
          : 'summary failure cannot suppress dispatch or lose older unknown retry',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final repo = SurfaceRepository()..failSavedSummary = true;
        await tester.pumpWidget(
          MaterialApp(
            home: ChatCloudPage(repository: repo, initialGroupId: 'line-only'),
          ),
        );
        await settle(tester);
        await tester.enterText(find.byType(TextField), 'First post');
        await tester.tap(find.byTooltip('送信'));
        await settle(tester);
        expect(repo.writes, 1);
        expect(repo.dispatches, ['saved-message']);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty,
        );
        expect(find.text('送信できませんでした'), findsNothing);
        if (holdRetry) {
          repo.retryGate = Completer<void>();
          await tester.tap(
            find.byKey(const ValueKey('line-retry-saved-message')),
          );
          await settle(tester);
        }
        await tester.enterText(find.byType(TextField), 'Second post');
        await tester.tap(find.byTooltip('送信'));
        await settle(tester);
        expect(repo.writes, 2);
        expect(
          repo.dispatches,
          holdRetry
              ? ['saved-message', 'saved-message', 'saved-message-2']
              : ['saved-message', 'saved-message-2'],
        );
        expect(
          find.byKey(const ValueKey('line-retry-saved-message')),
          findsOneWidget,
        );
        if (holdRetry) {
          repo.retryGate!.complete();
        } else {
          await tester.tap(
            find.byKey(const ValueKey('line-retry-saved-message')),
          );
        }
        await settle(tester);
        expect(repo.writes, 2);
        expect(repo.dispatches.where((id) => id == 'saved-message').length, 2);
        await tester.pumpWidget(const SizedBox());
        unawaited(repo.messages.close());
        await tester.pumpAndSettle();
      },
    );
  }
  testWidgets(
    'many unresolved posts stay individually retryable without overflowing composer',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final repo = SurfaceRepository()..allUnknown = true;
      await tester.pumpWidget(
        MaterialApp(
          home: ChatCloudPage(repository: repo, initialGroupId: 'line-only'),
        ),
      );
      await settle(tester);
      for (var i = 1; i <= 5; i++) {
        await tester.enterText(find.byType(TextField), 'Post $i');
        await tester.tap(find.byTooltip('送信'));
        await settle(tester);
      }
      expect(repo.writes, 5);
      expect(repo.dispatches.length, 5);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(
        find.byKey(const ValueKey('line-retry-saved-message-5')),
      );
      await tester.tap(
        find.byKey(const ValueKey('line-retry-saved-message-5')),
      );
      await settle(tester);
      expect(repo.writes, 5);
      expect(repo.dispatches.last, 'saved-message-5');
      await tester.pumpWidget(const SizedBox());
      unawaited(repo.messages.close());
      await tester.pumpAndSettle();
    },
  );
  for (final logout in [true, false]) {
    testWidgets(
      logout
          ? 'logout clears retries immediately and A-to-logout-to-A rejects old reply'
          : 'removed group mapping cannot resurrect its retry after an old reply',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final repo = SurfaceRepository();
        final actors = StreamController<String?>.broadcast();
        await tester.pumpWidget(
          MaterialApp(
            home: ChatCloudPage(
              repository: repo,
              actorChanges: actors.stream,
              initialGroupId: 'line-only',
            ),
          ),
        );
        await settle(tester);
        await tester.enterText(find.byType(TextField), 'Pending text');
        await tester.tap(find.byTooltip('送信'));
        await settle(tester);
        repo.retryGate = Completer<void>();
        await tester.tap(
          find.byKey(const ValueKey('line-retry-saved-message')),
        );
        await settle(tester);
        if (logout) {
          repo.actorId = null;
          actors.add(null);
          await settle(tester);
          expect(find.text('SKO保存済み・LINE送信未確認'), findsNothing);
          expect(find.text('Pending text'), findsNothing);
          repo.actorId = 'actor';
          actors.add('actor');
          await settle(tester);
        } else {
          repo.mapped = false;
          await tester.tap(find.byTooltip('再読み込み'));
          await settle(tester);
        }
        repo.retryGate!.complete();
        await settle(tester);
        expect(find.text('LINE受付済み（配信確認はLINE側で）'), findsNothing);
        expect(
          find.byKey(const ValueKey('line-retry-saved-message')),
          findsNothing,
        );
        expect(repo.writes, 1);
        await tester.pumpWidget(const SizedBox());
        unawaited(repo.messages.close());
        unawaited(actors.close());
        await tester.pumpAndSettle();
      },
    );
  }
  testWidgets('SKO conversation menu exposes authorized deletion and closes the deleted conversation', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = SurfaceRepository()..canDeleteGroup = true;
    await tester.pumpWidget(MaterialApp(home: ChatCloudPage(repository: repo, initialGroupId: 'shared')));
    await settle(tester);
    await tester.tap(find.byTooltip('トーク機能'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('グループを削除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('戻る'));
    await tester.pumpAndSettle();
    expect(repo.deletedGroups, isEmpty);
    await tester.tap(find.byTooltip('トーク機能'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('グループを削除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('グループを削除'));
    await settle(tester);
    expect(repo.deletedGroups, ['shared']);
    expect(find.text('Old message'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    unawaited(repo.messages.close());
    await tester.pumpAndSettle();
  });

  testWidgets('ordinary participants do not receive a group deletion menu', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = SurfaceRepository();
    await tester.pumpWidget(MaterialApp(home: ChatCloudPage(repository: repo, initialGroupId: 'shared')));
    await settle(tester);
    await tester.tap(find.byTooltip('トーク機能'));
    await tester.pumpAndSettle();
    expect(find.text('グループを削除'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    unawaited(repo.messages.close());
    await tester.pumpAndSettle();
  });

}
