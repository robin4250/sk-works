import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/main.dart';

void main() {
  testWidgets('SK WORKS home screen is shown', (tester) async {
    await tester.pumpWidget(const SkWorksApp());

    expect(find.text('SK WORKS'), findsWidgets);
    expect(find.text('社員・協力会社'), findsOneWidget);
    expect(find.text('資格管理'), findsOneWidget);
    expect(find.text('現場管理'), findsOneWidget);
    expect(find.text('勤怠・人工'), findsOneWidget);
    expect(find.text('請求管理'), findsOneWidget);
  });
}
