import 'support/line_test_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/chat/chat_cloud_page.dart';
import 'package:sk_works/features/chat/chat_cloud_repository.dart';
import 'package:sk_works/features/chat/line_joined_groups_page.dart';
import 'package:sk_works/features/chat/line_linked_talk_page.dart';

class _Repository implements ChatCloudRepository {
  String? actor = 'actor-a';
  bool master = true, selectable = true, linkable = true;
  bool companyVisible = true, linked = false;
  var groupReads = 0;
  final links = <String>[];

  Map<String, dynamic> get source => {
    'id': 'source-id', 'display_name': 'Actual LINE source',
    'joined': true, 'can_select': selectable,
    'primary_group_id': linked ? 'normal-group' : null,
    'read_target_group_id': linked ? 'normal-group' : null,
    'can_link': linkable, 'linked': false,
  };

  @override
  String? get currentUserId => actor;
  @override
  Future<bool> canRefreshLineDirectory() async => master;
  @override
  Future<List<Map<String, dynamic>>> loadJoinedLineGroups({
    String? targetGroupId, String? newGroupCompanyId,
  }) async => [source];
  @override
  Future<List<Map<String, dynamic>>> loadGroups() async {
    groupReads++;
    return [{
      'id': 'normal-group', 'name': 'Actual SKO group',
      'group_type': 'company', 'participants_only': true,
      'archived_at': null, 'can_edit_group_photo': true,
    }];
  }
  @override
  Future<String?> lineLinkCompanyName({
    String? groupId, String? creationCompanyId,
  }) async => companyVisible ? 'Actual company' : null;
  @override
  Future<void> linkLineSource(String groupId, String directoryId) async {
    links.add('$groupId:$directoryId');
    linked = true;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected repository operation: ${invocation.memberName}');
}

void main() {
  Future<void> open(WidgetTester tester, _Repository repository) async {
    await tester.pumpWidget(LineTestApp(
      home: LineJoinedGroupsPage(repository: repository),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> chooseExisting(WidgetTester tester) async {
    await tester.tap(find.text('Actual LINE source'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Actual SKO group'));
    await tester.pumpAndSettle();
  }

  testWidgets('unowned joined master source links only after company confirmation',
      (tester) async {
    final repository = _Repository();
    await open(tester, repository);
    expect(find.textContaining('連携してトークを開く'), findsOneWidget);
    await chooseExisting(tester);
    expect(repository.links, isEmpty);
    expect(find.textContaining('Actual company\nActual SKO group\nActual LINE source'),
      findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '追加'));
    await tester.pumpAndSettle();
    expect(repository.links, ['normal-group:source-id']);
    final page = tester.widget<LineLinkedTalkPage>(find.byType(LineLinkedTalkPage));
    expect(page.targetGroupId, 'normal-group');
    expect(page.directoryId, 'source-id');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('cancel does not link or make a source readable', (tester) async {
    final repository = _Repository();
    await open(tester, repository);
    await chooseExisting(tester);
    await tester.tap(find.widgetWithText(TextButton, '戻る'));
    await tester.pumpAndSettle();
    expect(repository.links, isEmpty);
    expect(find.byType(LineLinkedTalkPage), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('non-master and owned pending source remain blocked', (tester) async {
    for (final repository in [
      _Repository()..master = false,
      _Repository()..selectable = false,
    ]) {
      await open(tester, repository);
      expect(find.textContaining('連携してトークを開く'), findsNothing);
      expect(tester.widget<ListTile>(find.byType(ListTile)).onTap, isNull);
      expect(repository.groupReads, 0);
      expect(repository.links, isEmpty);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('changed target eligibility fails closed before confirmation',
      (tester) async {
    final repository = _Repository()..linkable = false;
    await open(tester, repository);
    await chooseExisting(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(repository.links, isEmpty);
    expect(find.byType(LineLinkedTalkPage), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('missing company name never gives the master a blank confirmation',
      (tester) async {
    final repository = _Repository()..companyVisible = false;
    await open(tester, repository);
    await chooseExisting(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(repository.links, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('actor change during confirmation sends no stale link',
      (tester) async {
    final repository = _Repository();
    await open(tester, repository);
    await chooseExisting(tester);
    repository.actor = 'actor-b';
    await tester.tap(find.widgetWithText(FilledButton, '追加'));
    await tester.pumpAndSettle();
    expect(repository.links, isEmpty);
    expect(find.byType(LineLinkedTalkPage), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('creation goes through the existing normal chat dialog with exact source',
      (tester) async {
    final repository = _Repository();
    await open(tester, repository);
    await tester.tap(find.text('Actual LINE source'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新しい通常グループを作成'));
    await tester.pumpAndSettle();
    final page = tester.widget<ChatCloudPage>(find.byType(ChatCloudPage));
    expect(page.createGroupInitially, true);
    expect(page.initialLineDirectoryId, 'source-id');
    expect(repository.links, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}
