import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/main.dart';

void main() {
  testWidgets('production app fails closed without Supabase', (tester) async {
    await tester.pumpWidget(const SkWorksApp());
    await tester.pump();

    expect(find.text('SKOを安全に開始できません'), findsOneWidget);
    expect(find.text('本日の出勤'), findsNothing);
    expect(find.text('請求書'), findsNothing);
    expect(find.text('人員管理'), findsNothing);
  });
}
