import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sk_works/main.dart';

void main() {
  testWidgets('SK WORKS home and employee module work', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const SkWorksApp());

    expect(find.text('SK WORKS'), findsWidgets);
    expect(find.text('社員・協力会社'), findsOneWidget);
    expect(find.text('資格管理'), findsOneWidget);
    expect(find.text('現場管理'), findsOneWidget);

    await tester.tap(find.text('社員・協力会社'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('山田 太郎'), findsOneWidget);
    expect(find.text('株式会社サンプル工業'), findsOneWidget);
    expect(find.text('新規登録'), findsOneWidget);
  });
}
