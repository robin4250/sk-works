import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/chat/chat_cloud_repository.dart';
import 'package:sk_works/features/chat/line_shared_groups_page.dart';
import 'package:sk_works/features/chat/line_shared_groups_repository.dart';

class FakeGroups implements LineSharedGroupsRepository {
  FakeGroups(this.rows, {this.fail = false});
  final List<Map<String, dynamic>> rows;
  final bool fail;
  String? actorId = 'fixture-actor';
  bool failDelete = false;
  final deletions = <String>[];
  @override
  String? get actor => actorId;
  @override
  Future<List<Map<String, dynamic>>> groups() async {
    if (fail) throw StateError('metadata unavailable');
    return rows;
  }
  @override
  Future<void> deleteGroup(String id) async {
    deletions.add(id);
    if (failDelete) throw StateError('permission changed');
    rows.removeWhere((row) => row['group_id'] == id);
  }
  @override
  Future<ChatConversationSummary?> preview(String id) async => null;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected operation: ${invocation.memberName}');
}

void main() {
  testWidgets(
    'LINE and SKO origins open the same canonical group without duplicating rows',
    (tester) async {
      String? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: LineSharedGroupsPage(
            repository: FakeGroups([
              {'group_id': 'shared', 'name': 'Shared group', 'origin': 'sko'},
              {'group_id': 'line-only', 'name': 'LINE group', 'origin': 'line'},
            ]),
            onOpenGroup: (id) async {
              opened = id;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Shared group'), findsOneWidget);
      expect(find.text('LINE group'), findsOneWidget);
      await tester.tap(find.text('Shared group'));
      expect(opened, 'shared');
    },
  );
  testWidgets(
    'metadata failure shows error and does not silently present a legacy list',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LineSharedGroupsPage(
            repository: FakeGroups([], fail: true),
            onOpenGroup: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('グループを読み込めませんでした。再読み込みしてください。'), findsOneWidget);
      expect(find.byType(ListTile), findsNothing);
    },
  );
  testWidgets('LINE group deletion names shared data, cancels safely and refreshes after confirmation', (tester) async {
    final repo = FakeGroups([{'group_id': 'g', 'name': '共有グループ', 'can_delete_group': true}]);
    await tester.pumpWidget(MaterialApp(home: LineSharedGroupsPage(repository: repo, onOpenGroup: (_) async {})));
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('line-delete-group-g'));
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.textContaining('LINE取込の月別表'), findsOneWidget);
    expect(find.textContaining('LINE本体のグループや履歴は削除されません'), findsOneWidget);
    await tester.tap(find.text('戻る'));
    await tester.pumpAndSettle();
    expect(repo.deletions, isEmpty);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.text('グループを削除'));
    await tester.pumpAndSettle();
    expect(repo.deletions, ['g']);
    expect(find.text('共有グループ'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unknown deletion permission hides the LINE group delete button', (tester) async {
    await tester.pumpWidget(MaterialApp(home: LineSharedGroupsPage(
      repository: FakeGroups([{'group_id': 'g', 'name': '共有グループ'}]), onOpenGroup: (_) async {})));
    await tester.pumpAndSettle();
    expect(find.byTooltip('グループを削除'), findsNothing);
  });

  testWidgets('changed actor cannot confirm deletion from an old dialog', (tester) async {
    final repo = FakeGroups([{'group_id': 'g', 'name': '共有グループ', 'can_delete_group': true}]);
    await tester.pumpWidget(MaterialApp(home: LineSharedGroupsPage(repository: repo, onOpenGroup: (_) async {})));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('line-delete-group-g')));
    await tester.pumpAndSettle();
    repo.actorId = 'other-actor';
    await tester.tap(find.text('グループを削除'));
    await tester.pumpAndSettle();
    expect(repo.deletions, isEmpty);
  });

  testWidgets('server rejection keeps the group and shows deletion could not be confirmed', (tester) async {
    final repo = FakeGroups([{'group_id': 'g', 'name': '共有グループ', 'can_delete_group': true}])..failDelete = true;
    await tester.pumpWidget(MaterialApp(home: LineSharedGroupsPage(repository: repo, onOpenGroup: (_) async {})));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('line-delete-group-g')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('グループを削除'));
    await tester.pumpAndSettle();
    expect(find.text('共有グループ'), findsOneWidget);
    expect(find.textContaining('削除結果を確認できませんでした'), findsOneWidget);
  });

}
