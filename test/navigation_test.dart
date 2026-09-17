import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sk_works/main.dart';

void main() {
  Future<void> openModule(
    WidgetTester tester,
    String menu,
    String expected,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const SkWorksApp());
    await tester.tap(find.text(menu));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(expected), findsWidgets);
  }

  testWidgets('home routes to people module', (tester) async {
    await openModule(tester, '社員・協力会社', '新規登録');
  });

  testWidgets('home routes to qualification module', (tester) async {
    await openModule(tester, '資格管理', '資格登録');
  });

  testWidgets('home routes to site module', (tester) async {
    await openModule(tester, '現場管理', '現場登録');
  });

  testWidgets('home routes to attendance module', (tester) async {
    await openModule(tester, '勤怠・人工', '出面入力');
  });

  testWidgets('home routes to invoice module', (tester) async {
    await openModule(tester, '請求管理', '請求作成');
  });

  testWidgets('home routes to settings module', (tester) async {
    await openModule(tester, '設定', '設定を保存');
  });
}
