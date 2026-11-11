import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sk_works/features/chat/chat_cloud_repository.dart';
import 'package:sk_works/features/chat/chat_friends_page.dart';

class _Repository implements ChatCloudRepository {
  String actor = 'self';
  final changes = StreamController<String?>.broadcast(sync: true);
  Completer<Map<String, dynamic>?>? search;
  Completer<void>? write;
  int loads = 0;
  final sent = <String>[];
  final responses = <bool>[];
  final removed = <String>[];
  @override
  String get currentUserId => actor;
  @override
  Stream<String?> watchActorChanges() => changes.stream;
  @override
  Future<Map<String, dynamic>> loadFriendWorkspace() async {
    loads++;
    return {'incoming': [{'id': 'request', 'display_name': '申請相手', 'sko_id': 'SKO-IN'}],
      'friends': [{'user_id': 'peer', 'display_name': '登録友達', 'sko_id': 'SKO-PEER'}]};
  }
  @override
  Future<Map<String, dynamic>?> searchFriendBySkoId(String id) async => search == null
      ? {'user_id': 'found', 'display_name': '検索相手', 'sko_id': 'SKO-FOUND'} : await search!.future;
  @override
  Future<void> sendFriendRequest(String id) async { sent.add(id); await write?.future; }
  @override
  Future<void> respondFriendRequest({required String requestId, required bool accept}) async { responses.add(accept); }
  @override
  Future<void> removeFriend(String id) async { removed.add(id); }
  void aba() { actor = 'other'; changes.add(actor); actor = 'self'; changes.add(actor); }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
Future<void> _start(WidgetTester tester, _Repository repo, {bool picker = false, Future<void> Function(BuildContext, String)? invite}) async {
  tester.view.physicalSize = const Size(1200, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(repo.changes.close);
  await tester.pumpWidget(MaterialApp(home: ChatFriendsPage(repository: repo, selectForChat: picker, onPhoneInvitation: invite)));
  await tester.pumpAndSettle();
}
Future<void> _search(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, 'SKO-FOUND');
  await tester.tap(find.byTooltip('検索'));
  await tester.pumpAndSettle();
}
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final failure in [false, true]) {
    testWidgets('delayed search ${failure ? 'error' : 'success'} discarded after actor ABA', (tester) async {
      final repo = _Repository()..search = Completer<Map<String, dynamic>?>();
      await _start(tester, repo);
      await tester.enterText(find.byType(TextField).first, 'SKO-FOUND');
      await tester.tap(find.byTooltip('検索')); await tester.pump();
      repo.aba(); await tester.pumpAndSettle();
      if (failure) { repo.search!.completeError(StateError('obsolete-search')); }
      else { repo.search!.complete({'display_name': 'OLD-RESULT', 'sko_id': 'SKO-OLD'}); }
      await tester.pumpAndSettle();
      expect(find.text('OLD-RESULT'), findsNothing);
      expect(find.textContaining('obsolete-search'), findsNothing);
      expect(find.textContaining('ログイン情報が変わりました'), findsOneWidget);
      expect(repo.sent, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
  for (final action in ['send', 'accept', 'decline', 'remove']) {
    testWidgets('$action confirmation cancelled on actor ABA without write', (tester) async {
      final repo = _Repository(); await _start(tester, repo);
      if (action == 'send') { await _search(tester); await tester.tap(find.text('申請')); }
      else { await tester.tap(find.byTooltip(action == 'accept' ? '承認' : action == 'decline' ? '拒否' : '友達から削除')); }
      await tester.pumpAndSettle(); expect(find.byType(AlertDialog), findsOneWidget);
      repo.aba(); await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(repo.sent, isEmpty); expect(repo.responses, isEmpty); expect(repo.removed, isEmpty);
    });
  }
  testWidgets('current confirmation sends once and cancel releases busy state', (tester) async {
    final repo = _Repository(); await _start(tester, repo); await _search(tester);
    final callback = tester.widget<FilledButton>(find.widgetWithText(FilledButton, '申請')).onPressed!;
    callback(); callback(); await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('戻る')); await tester.pumpAndSettle(); expect(repo.sent, isEmpty);
    await tester.tap(find.text('申請')); await tester.pumpAndSettle();
    await tester.tap(find.text('申請する')); await tester.pumpAndSettle();
    expect(repo.sent, ['SKO-FOUND']); expect(repo.loads, 2);
  });
  testWidgets('dispatched request completion cannot reload a changed actor', (tester) async {
    final repo = _Repository()..write = Completer<void>();
    await _start(tester, repo); await _search(tester);
    await tester.tap(find.text('申請')); await tester.pumpAndSettle();
    await tester.tap(find.text('申請する')); await tester.pumpAndSettle();
    expect(repo.sent, hasLength(1)); repo.aba(); await tester.pumpAndSettle();
    repo.write!.complete(); await tester.pumpAndSettle();
    expect(repo.loads, 1); expect(find.text('友達申請を送信しました'), findsNothing);
  });
  testWidgets('add-method sheet cancelled on actor ABA before external callback', (tester) async {
    final repo = _Repository(); final calls = <String>[];
    await _start(tester, repo, picker: true, invite: (_, source) async { calls.add(source); });
    await tester.tap(find.text('追加')); await tester.pumpAndSettle();
    expect(find.text('電話番号通知'), findsOneWidget);
    repo.aba(); await tester.pumpAndSettle();
    expect(find.text('電話番号通知'), findsNothing); expect(calls, isEmpty);
  });
  testWidgets('actor stream failure removes existing friends', (tester) async {
    final repo = _Repository(); await _start(tester, repo);
    expect(find.text('登録友達'), findsOneWidget);
    repo.changes.addError(StateError('synthetic stream unavailable')); await tester.pumpAndSettle();
    expect(find.text('登録友達'), findsNothing);
    expect(find.textContaining('ログイン情報が変わりました'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

