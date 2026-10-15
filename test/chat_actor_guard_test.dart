import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/chat/chat_actor_guard.dart';
import 'package:sk_works/features/chat/chat_direct_search_page.dart';

void main() {
  testWidgets('actor A to B to A permanently clears and closes search snapshot', (tester) async {
    final epoch = ValueNotifier<int>(0);
    addTearDown(epoch.dispose);
    String? selection;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return TextButton(onPressed: () async {
        final initialEpoch = epoch.value;
        selection = await Navigator.push<String>(context, MaterialPageRoute(
          builder: (_) => ChatActorGuard(
            epoch: epoch, initialEpoch: initialEpoch,
            child: const ChatDirectSearchPage(peerName: '友達', messages: [
              {'id': 'm', 'body': '旧利用者の秘密本文'},
            ]),
          ),
        ));
      }, child: const Text('開く'));
    })));
    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '秘密');
    await tester.pump();
    expect(find.text('旧利用者の秘密本文'), findsOneWidget);
    epoch.value = 1;
    epoch.value = 2;
    await tester.pumpAndSettle();
    expect(find.text('旧利用者の秘密本文'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('開く'), findsOneWidget);
    expect(selection, isNull);
  });

  testWidgets('an already stale route never exposes its child', (tester) async {
    final epoch = ValueNotifier<int>(2);
    addTearDown(epoch.dispose);
    await tester.pumpWidget(MaterialApp(home: ChatActorGuard(
      epoch: epoch, initialEpoch: 0,
      child: const Text('再表示してはいけない旧プロフィール'),
    )));
    expect(find.text('再表示してはいけない旧プロフィール'), findsNothing);
  });
}
