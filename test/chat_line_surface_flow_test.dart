import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sk_works/features/chat/chat_cloud_page.dart';
import 'package:sk_works/features/chat/chat_cloud_repository.dart';

class SurfaceRepository implements ChatCloudRepository {
  int writes = 0;
  bool failSavedSummary = false;
  Completer<void>? retryGate;
  final dispatches = <String>[];
  final messages = StreamController<List<Map<String, dynamic>>>.broadcast();
  @override
  String? get currentUserId => 'actor';
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
      'line_origin': 'line',
    },
    {
      'id': 'shared',
      'name': 'Shared group',
      'display_name': 'Shared group',
      'group_type': 'company',
      'participants_only': true,
      'line_origin': 'sko',
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
    return dispatches.length == 1 ? 'unknown' : 'accepted';
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
      await repo.messages.close();
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
      await repo.messages.close();
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
        await repo.messages.close();
      },
    );
  }
}
