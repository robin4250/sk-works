import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/expenses/expense_home_page.dart';
import 'package:sk_works/features/expenses/expense_surface_card.dart';

void main() {
  testWidgets('expense entry keeps both routes readable on a narrow enlarged screen',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(1.3)),
          child: child!),
        home: const ExpenseHomePage()));
      expect(find.byType(ExpenseSurfaceCard), findsNWidgets(2));
      expect(find.text('自分の経費申請'), findsOneWidget);
      expect(find.text('全員の申請・振り分け'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '開く'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
}
