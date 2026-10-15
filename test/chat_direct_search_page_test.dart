import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/features/chat/chat_direct_search_page.dart';

void main() {
  testWidgets(
    'direct search shows matching body sender and time and returns exact id',
    (tester) async {
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              child: const Text('検索'),
              onPressed: () async {
                selected = await Navigator.push<String>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ChatDirectSearchPage(
                      peerName: '友達',
                      messages: [
                        {
                          'id': 'match',
                          'body': '住所は東京都です',
                          'sender_display_name': '友達',
                          'sent_at': '2026-10-15 10:00',
                        },
                        {
                          'id': 'other',
                          'body': 'お疲れ様です',
                          'sender_display_name': '自分',
                          'sent_at': '2026-10-15 10:01',
                        },
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('検索'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '住所');
      await tester.pump();
      expect(find.text('住所は東京都です'), findsOneWidget);
      expect(find.text('お疲れ様です'), findsNothing);
      expect(find.textContaining('2026-10-15 10:00'), findsOneWidget);
      await tester.tap(find.text('住所は東京都です'));
      await tester.pumpAndSettle();
      expect(selected, 'match');
    },
  );
}
