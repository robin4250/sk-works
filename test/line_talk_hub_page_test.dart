import 'support/line_test_app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/chat/line_talk_hub_page.dart';
import 'package:sk_works/features/chat/line_shared_groups_page.dart';

void main() {
  testWidgets('confirmed LINE capability remains independent of optional import features', (tester) async {
    await tester.pumpWidget(const LineTestApp(home: LineTalkHubPage()));
    await tester.pump();
    expect(find.text('トーク'), findsOneWidget);
    expect(find.text('出勤表'), findsNothing);
    expect(find.text('請求書'), findsNothing);
    await tester.tap(find.text('トーク'));
    await tester.pumpAndSettle();
    expect(find.byType(LineSharedGroupsPage), findsOneWidget);
    expect(find.text('LINEグループから作成'), findsOneWidget);
    expect(find.text('保存済みトーク'), findsOneWidget);
    expect(find.text('SKOへのログインが必要です。'), findsOneWidget);
  });
}

