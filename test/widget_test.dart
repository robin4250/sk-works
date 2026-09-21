import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sk_works/main.dart';

void main() {
  testWidgets('SKO admin home uses finalized dashboard labels', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const SkWorksApp(allowLocalFallback: true));
    await tester.pump();

    expect(find.text('SKO'), findsWidgets);
    expect(find.text('本日の出勤'), findsWidgets);
    expect(find.text('承認待ち'), findsOneWidget);
    expect(find.text('出勤・人区管理'), findsOneWidget);
    expect(find.text('人員管理'), findsOneWidget);
    expect(find.text('請求書'), findsOneWidget);
    expect(find.text('管理者用現場データ'), findsOneWidget);
  });
}
