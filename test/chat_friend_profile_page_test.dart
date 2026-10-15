import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sk_works/features/chat/chat_friend_profile_page.dart';

void main() {
  testWidgets(
    'friend detail exposes approved identity only and returns chat intent',
    (tester) async {
      bool? startChat;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () async {
                  startChat = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => const ChatFriendProfilePage(
                        friend: {
                          'user_id': 'friend-1',
                          'display_name': '友達の名前',
                          'sko_id': 'SKO-TEST',
                          'address': '非公開住所',
                          'salary': '非公開給与',
                        },
                      ),
                    ),
                  );
                },
                child: const Text('開く'),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('開く'));
      await tester.pumpAndSettle();
      expect(find.text('友達の名前'), findsOneWidget);
      expect(find.text('SKO-TEST'), findsOneWidget);
      expect(find.text('非公開住所'), findsNothing);
      expect(find.text('非公開給与'), findsNothing);
      expect(startChat, isNull);
      await tester.tap(find.text('チャットを始める'));
      await tester.pumpAndSettle();
      expect(startChat, isTrue);
    },
  );

  testWidgets('invalid friend cannot start chat', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ChatFriendProfilePage(friend: {})),
    );
    final button = tester.widget<FilledButton>(
      find.byWidgetPredicate((widget) => widget is FilledButton),
    );
    expect(button.onPressed, isNull);
  });
}
