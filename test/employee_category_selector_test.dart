import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/people/employee_category_selector.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('区分の導入前だけ既存編集を継続できる旨を表示する', () {
    const missing = PostgrestException(code: 'PGRST202',
      message: 'Could not find the function public.ensure_employee_categories(p_company) in the schema cache');
    expect(employeeCategoryLoadMessage(missing, hasSavedCategory: false),
      '従業員区分は現在利用できません。社員情報は引き続き編集できます。');
    expect(employeeCategoryLoadMessage(missing, hasSavedCategory: true),
      '区分を読み込めません。再読み込みしてください。');
    for (final error in <Object>[
      const PostgrestException(code: 'PGRST202', message: 'public.list_employee_categories not found'),
      const PostgrestException(code: '42501', message: 'public.ensure_employee_categories denied'),
      const PostgrestException(code: 'PGRST202', message: 'public.ensure_employee_categories_other not found'),
      StateError('network'),
    ]) {
      expect(employeeCategoryLoadMessage(error, hasSavedCategory: false),
        '区分を読み込めません。再読み込みしてください。');
    }
  });
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
