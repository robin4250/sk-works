import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/chat/line_talk_hub_page.dart';

void main() {
  testWidgets('public talk remains available when paid import features are unavailable', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LineTalkHubPage()));
    await tester.pump();
    expect(find.text('トーク'), findsOneWidget);
    expect(find.text('出勤表'), findsNothing);
    expect(find.text('請求書'), findsNothing);
    await tester.tap(find.text('トーク'));
    await tester.pumpAndSettle();
    expect(find.text('SKOへのログインが必要です。'), findsOneWidget);
  });
}
