import 'support/line_test_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/chat/line_talk_hub_page.dart';
import 'package:sk_works/features/chat/line_joined_groups_page.dart';
void main() {
 testWidgets('joined directory has separate hub button and login safe page', (tester) async {
  await tester.pumpWidget(const LineTestApp(home:LineTalkHubPage()));await tester.pump();
  expect(find.text('参加済みグループ一覧'),findsOneWidget);expect(find.text('トーク'),findsOneWidget);
  await tester.tap(find.text('参加済みグループ一覧'));await tester.pumpAndSettle();
  expect(find.byType(LineJoinedGroupsPage),findsOneWidget);expect(find.text('SKOへのログインが必要です。'),findsOneWidget);
  await tester.pumpWidget(const SizedBox());
 });
}
