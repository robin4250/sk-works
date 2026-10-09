import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/chat/chat_cloud_repository.dart';
import 'package:sk_works/features/chat/chat_friends_page.dart';
import 'package:sk_works/international/language_controller.dart';
import 'package:sk_works/international/language_pack_registry.dart';

const person = <String, dynamic>{
  'id': 'request-1',
  'user_id': 'user-1',
  'display_name': '山田 {name} 太郎',
  'sko_id': 'SKO-ABCDEFGHIJ',
};

class FriendsRepository implements ChatCloudRepository {
  Map<String, dynamic> workspace = {
    'my_sko_id': 'SKO-0123456789',
    'friends': <Map<String, dynamic>>[],
  };
  Map<String, dynamic>? result = person;
  Object? failure;
  int loads = 0;
  final searched = <String>[];
  final sent = <String>[];
  final responses = <(String, bool)>[];
  final removed = <String>[];

  @override
  Future<Map<String, dynamic>> loadFriendWorkspace() async {
    loads++;
    if (failure != null) throw failure!;
    return workspace;
  }

  @override
  Future<Map<String, dynamic>?> searchFriendBySkoId(String skoId) async {
    searched.add(skoId);
    if (failure != null) throw failure!;
    return result;
  }

  @override
  Future<void> sendFriendRequest(String skoId) async {
    sent.add(skoId);
    if (failure != null) throw failure!;
  }

  @override
  Future<void> respondFriendRequest({
    required String requestId,
    required bool accept,
  }) async {
    responses.add((requestId, accept));
    if (failure != null) throw failure!;
  }

  @override
  Future<void> removeFriend(String userId) async {
    removed.add(userId);
    if (failure != null) throw failure!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> showPage(
  WidgetTester tester,
  Widget page, {
  String language = 'en',
}) async {
  SkoLanguageController.pack.value = LanguagePackRegistry.resolve(language);
  await tester.pumpWidget(
    ValueListenableBuilder(
      valueListenable: SkoLanguageController.pack,
      builder: (_, pack, _) => MaterialApp(
        locale: Locale(pack.languageCode),
        supportedLocales: const [Locale('ja'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: page,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    final original = SkoLanguageController.pack.value;
    addTearDown(() => SkoLanguageController.pack.value = original);
  });

  testWidgets(
    'live language switch preserves input, results, names and repository calls',
    (tester) async {
      final repo = FriendsRepository();
      await showPage(tester, ChatFriendsPage(repository: repo), language: 'ja');
      await tester.enterText(find.byType(TextField), '  SKO-ABCDEFGHIJ  ');
      await tapVisible(tester, find.text('検索'));
      expect(repo.searched, ['SKO-ABCDEFGHIJ']);
      final state = tester.state(find.byType(ChatFriendsPage));
      SkoLanguageController.pack.value = LanguagePackRegistry.resolve('en');
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(ChatFriendsPage)), same(state));
      expect(find.text('Friends'), findsOneWidget);
      expect(find.text('My SKO ID'), findsOneWidget);
      expect(find.text('Search by SKO ID'), findsOneWidget);
      expect(find.text('No friends yet'), findsOneWidget);
      expect(find.text(person['display_name']), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '  SKO-ABCDEFGHIJ  ',
      );
      expect(repo.loads, 1);
      await tapVisible(tester, find.text('Request'));
      expect(
        find.text('Send a friend request to 山田 {name} 太郎.'),
        findsOneWidget,
      );
      SkoLanguageController.pack.value = LanguagePackRegistry.resolve('ja');
      await tester.pumpAndSettle();
      expect(find.text('友達申請を送りますか？'), findsOneWidget);
      expect(find.text('山田 {name} 太郎 さんへ友達申請を送信します。'), findsOneWidget);
      await tapVisible(tester, find.text('戻る'));
      expect(repo.sent, isEmpty);
      await tapVisible(tester, find.text('申請'));
      await tapVisible(tester, find.text('申請する'));
      expect(repo.sent, ['SKO-ABCDEFGHIJ']);
      expect(find.text('友達申請を送信しました'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'incoming, outgoing and friend actions keep their original identifiers',
    (tester) async {
      final repo = FriendsRepository()
        ..workspace = {
          'incoming': [person],
          'outgoing': [person],
          'friends': [person],
        };
      await showPage(tester, ChatFriendsPage(repository: repo));
      expect(find.text('Incoming requests'), findsOneWidget);
      await tapVisible(tester, find.byTooltip('Accept'));
      expect(find.text('Accept this friend request?'), findsOneWidget);
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Accept'));
      expect(repo.responses, [('request-1', true)]);
      await tapVisible(tester, find.byTooltip('Decline'));
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Decline'));
      expect(repo.responses.last, ('request-1', false));
      await tapVisible(tester, find.byTooltip('Remove friend'));
      expect(find.text('Remove this friend?'), findsOneWidget);
      await tapVisible(tester, find.text('Back'));
      expect(repo.removed, isEmpty);
      await tapVisible(tester, find.byTooltip('Remove friend'));
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Remove'));
      expect(repo.removed, ['user-1']);
      expect(tester.takeException(), isNull);
    },
  );

  for (final group in [false, true]) {
    testWidgets('selection mode group=$group returns the unchanged friend', (
      tester,
    ) async {
      final repo = FriendsRepository()
        ..workspace = {
          'friends': [person],
        };
      Map<String, dynamic>? selected;
      await showPage(
        tester,
        Builder(
          builder: (context) => TextButton(
            child: const Text('Open'),
            onPressed: () async => selected = await Navigator.of(context)
                .push<Map<String, dynamic>>(
                  MaterialPageRoute(
                    builder: (_) => ChatFriendsPage(
                      repository: repo,
                      selectForChat: !group,
                      selectForGroupInvite: group,
                    ),
                  ),
                ),
          ),
        ),
      );
      await tapVisible(tester, find.text('Open'));
      expect(
        find.text(group ? 'Invite friends' : 'Friends list'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
      await tapVisible(tester, find.text(person['display_name']));
      expect(selected, person);
      expect(repo.sent, isEmpty);
      expect(repo.removed, isEmpty);
    });
  }

  testWidgets(
    'unavailable and failed load messages follow the active language',
    (tester) async {
      await showPage(tester, const ChatFriendsPage());
      expect(find.text('Friends are unavailable.'), findsOneWidget);
      SkoLanguageController.pack.value = LanguagePackRegistry.resolve('ja');
      await tester.pumpAndSettle();
      expect(find.text('友達機能を利用できません。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      final repo = FriendsRepository()..failure = 'fixture detail';
      await showPage(tester, ChatFriendsPage(repository: repo));
      expect(
        find.text('Could not load friends: fixture detail'),
        findsOneWidget,
      );
      SkoLanguageController.pack.value = LanguagePackRegistry.resolve('ja');
      await tester.pumpAndSettle();
      expect(find.text('友達一覧を読み込めませんでした: fixture detail'), findsOneWidget);
    },
  );

  testWidgets(
    'failed response and removal show feedback and leave rows intact',
    (tester) async {
      final repo = FriendsRepository()
        ..workspace = {
          'incoming': [person],
          'friends': [person],
        };
      await showPage(tester, ChatFriendsPage(repository: repo));
      repo.failure = 'fixture detail';
      await tapVisible(tester, find.byTooltip('Accept'));
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Accept'));
      expect(
        find.text('Could not update the friend request: fixture detail'),
        findsOneWidget,
      );
      expect(repo.loads, 1);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byTooltip('Remove friend'));
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Remove'));
      expect(
        find.text('Could not remove the friend: fixture detail'),
        findsOneWidget,
      );
      expect(repo.loads, 1);
      expect(find.byTooltip('Remove friend'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('missing display name follows the language of an open dialog', (
    tester,
  ) async {
    final repo = FriendsRepository()..result = {'sko_id': 'SKO-ABCDEFGHIJ'};
    await showPage(tester, ChatFriendsPage(repository: repo), language: 'ja');
    await tester.enterText(find.byType(TextField), 'SKO-ABCDEFGHIJ');
    await tapVisible(tester, find.text('検索'));
    await tapVisible(tester, find.text('申請'));
    SkoLanguageController.pack.value = LanguagePackRegistry.resolve('en');
    await tester.pumpAndSettle();
    expect(find.text('Send a friend request to SKO user.'), findsOneWidget);
    await tapVisible(tester, find.text('Back'));
    expect(repo.sent, isEmpty);
  });

  testWidgets(
    'search and send failures show English feedback without losing input',
    (tester) async {
      final repo = FriendsRepository()..result = null;
      await showPage(tester, ChatFriendsPage(repository: repo));
      await tester.enterText(find.byType(TextField), 'SKO-ABCDEFGHIJ');
      await tapVisible(tester, find.text('Search'));
      expect(find.text('No matching SKO ID found'), findsOneWidget);
      final messenger = tester.state<ScaffoldMessengerState>(
        find.byType(ScaffoldMessenger),
      );
      messenger.removeCurrentSnackBar();
      repo.failure = 'fixture detail';
      await tapVisible(tester, find.text('Search'));
      expect(find.text('Could not search: fixture detail'), findsOneWidget);
      messenger.removeCurrentSnackBar();
      repo.failure = null;
      repo.result = person;
      await tapVisible(tester, find.text('Search'));
      repo.failure = 'fixture detail';
      await tapVisible(tester, find.text('Request'));
      await tapVisible(tester, find.text('Send request'));
      expect(
        find.text('Could not send the friend request: fixture detail'),
        findsOneWidget,
      );
      expect(find.text('Friend request sent'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'SKO-ABCDEFGHIJ',
      );
      expect(repo.loads, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('narrow English search result stays usable with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final repo = FriendsRepository();
    await showPage(tester, ChatFriendsPage(repository: repo));
    await tester.enterText(find.byType(TextField), 'SKO-ABCDEFGHIJ');
    await tapVisible(tester, find.text('Search'));
    await tapVisible(tester, find.text('Request'));
    expect(find.text('Send a friend request?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
