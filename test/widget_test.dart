import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sk_works/main.dart';

void main() {
  testWidgets('SKO friendly admin home and people module work', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const SkWorksApp());

    expect(find.text('SKO'), findsWidgets);
    expect(find.text('管理ホーム'), findsOneWidget);
    expect(find.text('人員'), findsOneWidget);
    expect(find.text('現場'), findsOneWidget);
    expect(find.text('出勤表'), findsOneWidget);
    expect(find.text('請求'), findsOneWidget);

    await tester.tap(find.text('人員'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('山田 太郎'), findsOneWidget);
    expect(find.text('株式会社サンプル工業'), findsOneWidget);
    expect(find.text('新規登録'), findsOneWidget);
  });
}
