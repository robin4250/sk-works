import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/people/employee_category_selector.dart';

void main() {
  testWidgets('未設定は自動で区分を選択しない', (tester) async {
    String? selection;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      EmployeeCategorySelector(options: const [
        EmployeeCategoryOption(id: 'full', name: '正社員'),
        EmployeeCategoryOption(id: 'temp', name: '派遣社員'),
        EmployeeCategoryOption(id: 'part', name: 'アルバイト')],
        selectedId: null, onChanged: (value) => selection = value))));
    expect(find.text('未設定'), findsOneWidget);
    expect(selection, isNull);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('派遣社員').last);
    await tester.pumpAndSettle();
    expect(selection, 'temp');
  });
  testWidgets('使用停止済みの選択値は表示を保持する', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      EmployeeCategorySelector(options: const [
        EmployeeCategoryOption(id: 'old', name: '区分A', active: false)],
        selectedId: 'old', onChanged: (_) {}))));
    expect(find.text('区分A（使用停止）'), findsOneWidget);
  });
}
