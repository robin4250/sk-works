import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sk_works/features/chat/chat_cloud_page.dart';
import 'package:sk_works/features/chat/chat_cloud_repository.dart';

import 'support/line_test_app.dart';

const target = '11111111-1111-4111-8111-111111111111';
const other = '22222222-2222-4222-8222-222222222222';
const group = '33333333-3333-4333-8333-333333333333';
Map<String, dynamic> invite(String id, String name) => {
  'id': id,
  'group_id': group,
  'group_name': name,
  'inviter_name': 'Inviter',
};

class _Repository implements ChatCloudRepository {
  String? actor = 'actor-a';
  List<Map<String, dynamic>> rows = [
    invite(target, 'Exact invitation'),
    invite(other, 'Other invitation'),
  ];
  Completer<List<Map<String, dynamic>>>? gate;
  final replies = <(String, bool)>[];
  Completer<void>? replyGate;
  @override
  String? get currentUserId => actor;
  @override
  Future<({String companyId, String role})> membership() async =>
      (companyId: 'company', role: 'owner');
  @override
  Future<bool> canManagePartnerChat() async => false;
  @override
  Future<List<Map<String, dynamic>>> loadGroups() async => [];
  @override
  Future<List<String>> prioritizedSiteGroupIds() async => [];
  @override
  Future<Set<String>> loadBlockedUserIds() async => {};
  @override
  Future<Map<String, dynamic>> loadFriendWorkspace() async => {};
  @override
  Future<List<Map<String, dynamic>>> loadPendingGroupInvites() async =>
      gate == null ? List.of(rows) : gate!.future;
  @override
  Stream<String> watchConversationChanges() => const Stream.empty();
  @override
  Future<String> respondGroupInvite({
    required String inviteId,
    required bool accept,
  }) async {
    replies.add((inviteId, accept));
    await replyGate?.future;
    rows.removeWhere((row) => row['id'] == inviteId);
    return ''; // The test does not join or open a conversation.
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected operation: ${invocation.memberName}');
}

Finder _button(String tooltip) => find.byWidgetPredicate(
  (widget) => widget is IconButton && widget.tooltip == tooltip,
);

Future<void> _show(
  WidgetTester tester,
  _Repository repository,
  String? id, {
  Stream<String?>? actors,
}) async {
  await tester.pumpWidget(
    LineTestApp(
      home: ChatCloudPage(
        repository: repository,
        initialInviteId: id,
        showGroupsInitially: true,
        actorChanges: actors,
      ),
    ),
  );
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'normal null entry retains every pending invitation without writes',
    (tester) async {
      final repository = _Repository();
      await _show(tester, repository, null);
      expect(find.text('Exact invitation'), findsOneWidget);
      expect(find.text('Other invitation'), findsOneWidget);
      expect(repository.replies, isEmpty);
    },
  );

  for (final accept in [false, true]) {
    testWidgets(
      'exact invitation UUID selects only its row; explicit accept=$accept uses original UUID',
      (tester) async {
        final repository = _Repository();
        await _show(tester, repository, target);
        expect(find.text('Exact invitation'), findsOneWidget);
        expect(find.text('Other invitation'), findsNothing);
        expect(repository.replies, isEmpty);
        await tester.tap(_button(accept ? '承認' : '拒否'));
        await tester.pumpAndSettle();
        expect(repository.replies, [(target, accept)]);
        expect(find.text('Other invitation'), findsNothing);
        expect(find.text('対象の招待は完了済み、または閲覧できません。'), findsOneWidget);
      },
    );
  }

  for (final id in [
    '',
    'not-a-uuid',
    group,
    '44444444-4444-4444-8444-444444444444',
  ]) {
    testWidgets(
      'missing/invalid target $id never falls back to a different invitation',
      (tester) async {
        final repository = _Repository();
        await _show(tester, repository, id);
        expect(find.text('Exact invitation'), findsNothing);
        expect(find.text('Other invitation'), findsNothing);
        expect(_button('承認'), findsNothing);
        expect(find.text('対象の招待は完了済み、または閲覧できません。'), findsOneWidget);
        expect(repository.replies, isEmpty);
      },
    );
  }

  testWidgets(
    'actor ABA clears visible invitation and rejects captured old callback',
    (tester) async {
      final repository = _Repository();
      final actors = StreamController<String?>.broadcast(sync: true);
      await _show(tester, repository, target, actors: actors.stream);
      final oldAction = tester.widget<IconButton>(_button('承認')).onPressed!;
      repository.gate = Completer<List<Map<String, dynamic>>>();
      repository.actor = 'actor-b';
      actors.add('actor-b');
      repository.actor = 'actor-a';
      actors.add('actor-a');
      await tester.pump();
      oldAction();
      expect(repository.replies, isEmpty);
      expect(find.text('Exact invitation'), findsNothing);
      repository.gate!.complete([]);
      await tester.pumpAndSettle();
      expect(find.text('Exact invitation'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await actors.close();
    },
  );

  testWidgets(
    'late original actor response after ABA cannot restore old invitation',
    (tester) async {
      final repository = _Repository()
        ..gate = Completer<List<Map<String, dynamic>>>();
      final oldGate = repository.gate!;
      final actors = StreamController<String?>.broadcast(sync: true);
      await _show(tester, repository, target, actors: actors.stream);
      repository.gate = Completer<List<Map<String, dynamic>>>();
      repository.actor = 'actor-b';
      actors.add('actor-b');
      repository.actor = 'actor-a';
      actors.add('actor-a');
      await tester.pump();
      oldGate.complete([invite(target, 'Old actor invitation')]);
      repository.gate!.complete([]);
      await tester.pumpAndSettle();
      expect(find.text('Old actor invitation'), findsNothing);
      expect(repository.replies, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await actors.close();
    },
  );

  for (final failOld in [false, true]) {
    testWidgets(
      'changing target suppresses late old response; error=$failOld',
      (tester) async {
        final repository = _Repository()
          ..gate = Completer<List<Map<String, dynamic>>>();
        final oldGate = repository.gate!;
        await _show(tester, repository, target);
        repository.gate = Completer<List<Map<String, dynamic>>>();
        await _show(tester, repository, other);
        repository.gate!.complete([
          invite(target, 'Old target invitation'),
          invite(other, 'Current target invitation'),
        ]);
        await tester.pumpAndSettle();
        expect(find.text('Current target invitation'), findsOneWidget);
        if (failOld) {
          oldGate.completeError(StateError('stale target read failed'));
        } else {
          oldGate.complete([invite(target, 'Late old invitation')]);
        }
        await tester.pumpAndSettle();
        expect(find.text('Current target invitation'), findsOneWidget);
        expect(find.text('Late old invitation'), findsNothing);
        expect(find.textContaining('stale target read failed'), findsNothing);
        expect(repository.replies, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final entry in <String?>[null, target]) {
    for (final accept in [false, true]) {
      testWidgets(
        'pending reply blocks repeated callback and opposite action; accept=$accept target=$entry',
        (tester) async {
          final repository = _Repository()..replyGate = Completer<void>();
          await _show(tester, repository, entry);
          final action = tester
              .widget<IconButton>(_button(accept ? '承認' : '拒否').first)
              .onPressed!;
          final opposite = tester
              .widget<IconButton>(_button(accept ? '拒否' : '承認').first)
              .onPressed!;
          action();
          action();
          opposite();
          await tester.pump();
          expect(repository.replies, [(target, accept)]);
          expect(
            tester.widget<IconButton>(_button('承認').first).onPressed,
            isNull,
          );
          expect(
            tester.widget<IconButton>(_button('拒否').first).onPressed,
            isNull,
          );
          repository.replyGate!.complete();
          await tester.pumpAndSettle();
          expect(repository.replies, [(target, accept)]);
        },
      );
    }
  }

  testWidgets('response after dispose causes no display or write', (
    tester,
  ) async {
    final repository = _Repository()
      ..gate = Completer<List<Map<String, dynamic>>>();
    await _show(tester, repository, target);
    await tester.pumpWidget(const SizedBox());
    repository.gate!.complete([invite(target, 'Disposed invitation')]);
    await tester.pumpAndSettle();
    expect(find.text('Disposed invitation'), findsNothing);
    expect(repository.replies, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
