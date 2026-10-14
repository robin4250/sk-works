import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/chat/chat_cloud_page.dart';
import 'package:sk_works/features/chat/chat_cloud_repository.dart';
import 'package:sk_works/features/chat/line_shared_groups_page.dart';
import 'package:sk_works/features/chat/line_shared_groups_repository.dart';
import 'package:sk_works/features/chat/line_talk_hub_page.dart';

class _Groups implements LineSharedGroupsRepository {
  String? actorId = 'actor';
  bool removed = false;
  final requested = <String>[];
  Completer<void>? gate;
  @override
  String? get actor => actorId;
  @override
  Future<List<Map<String, dynamic>>> groups() async => [
    if (!removed) {'group_id': 'a', 'name': 'Group A', 'last_message_body': 'Previous A'},
    {'group_id': 'b', 'name': 'Group B', 'last_message_body': 'Previous B'},
  ];
  @override
  Future<ChatConversationSummary?> preview(String id) async {
    requested.add(id);
    if (removed && id == 'a') return null;
    await gate?.future;
    return const ChatConversationSummary(unread: 0, body: 'Latest A',
      sentAt: '2026-10-14T00:00:00Z');
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('Unexpected operation');
}
void main() {
  testWidgets('LINE Talk opens a list and its group opens the canonical writable chat', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LineTalkHubPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('トーク'));
    await tester.pumpAndSettle();
    expect(find.byType(LineSharedGroupsPage), findsOneWidget);
    expect(find.text('LINEグループから作成'), findsOneWidget);
    expect(find.text('保存済みトーク'), findsOneWidget);
    final page = tester.widget<LineSharedGroupsPage>(find.byType(LineSharedGroupsPage));
    final opening = page.onOpenGroup('canonical-group');
    await tester.pumpAndSettle();
    expect(tester.widget<ChatCloudPage>(find.byType(ChatCloudPage)).initialGroupId, 'canonical-group');
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    await opening;
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('LINE list refreshes only the changed group and rejects stale actor results', (tester) async {
    final repo = _Groups();
    final changes = StreamController<String>.broadcast();
    final opened = <String>[];
    await tester.pumpWidget(MaterialApp(home: LineSharedGroupsPage(
      repository: repo, groupChanges: changes.stream,
      onOpenGroup: (id) async { opened.add(id); },
    )));
    await tester.pumpAndSettle();
    expect(find.text('Previous A'), findsOneWidget);
    changes.add('a');
    await tester.pumpAndSettle();
    expect(repo.requested, ['a']);
    expect(find.text('Latest A'), findsOneWidget);
    expect(find.text('Previous B'), findsOneWidget);
    await tester.tap(find.text('Group A'));
    await tester.pumpAndSettle();
    expect(opened, ['a']);
    expect(repo.requested, ['a', 'a']);
    repo.gate = Completer<void>();
    changes.add('b');
    await tester.pump();
    repo.actorId = 'other-actor';
    repo.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Previous B'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await changes.close();
  });
  testWidgets('returning from a deleted shared chat removes it from the LINE list', (tester) async {
    final repo = _Groups();
    await tester.pumpWidget(MaterialApp(home: LineSharedGroupsPage(
      repository: repo, onOpenGroup: (_) async { repo.removed = true; })));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Group A'));
    await tester.pumpAndSettle();
    expect(find.text('Group A'), findsNothing);
    expect(find.text('Group B'), findsOneWidget);
  });

}
