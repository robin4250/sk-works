import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sk_works/features/attendance/attendance_page.dart';

void main() {
  testWidgets('attendance page shows sample entries and totals', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: AttendancePage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('山田 太郎'), findsOneWidget);
    expect(find.textContaining('佐藤 次郎'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('2h'), findsOneWidget);
    expect(find.text('出面入力'), findsOneWidget);
  });

  testWidgets('attendance search filters by worker', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: AttendancePage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.enterText(find.byType(TextField), '山田');
    await tester.pump();

    expect(find.textContaining('山田 太郎'), findsOneWidget);
    expect(find.textContaining('佐藤 次郎'), findsNothing);
  });
}
