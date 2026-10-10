import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/expenses/expense_claim.dart';
import 'package:sk_works/features/expenses/expense_claims_page.dart';
import 'expense_fixture.dart';

void main() {
  testWidgets('unconnected all list shows every status and disables writes', (
    tester,
  ) async {
    final claims = ExpenseClaims(
      companyId: 'company',
      claims: [
        expenseFixture('p'),
        expenseFixture('a', applicant: 'other', name: '別の社員').approve(),
        expenseFixture('r').reject(),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(home: ExpenseClaimsPage(claims: claims)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('p')), findsOneWidget);
    expect(find.byKey(const ValueKey('a')), findsOneWidget);
    expect(find.byKey(const ValueKey('r')), findsOneWidget);
    expect(find.textContaining('未承認 /'), findsOneWidget);
    expect(find.textContaining('却下 /'), findsOneWidget);
    for (final button in tester.widgetList<TextButton>(
      find.widgetWithText(TextButton, '承認'),
    )) {
      expect(button.onPressed, isNull);
    }
    await tester.tap(find.text('別の社員'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('a')), findsOneWidget);
    expect(find.byKey(const ValueKey('p')), findsNothing);
    expect(find.byKey(const ValueKey('r')), findsNothing);
  });
  testWidgets(
    'callback pending prevents duplicate writes and failure does not approve locally',
    (tester) async {
      final response = Completer<void>();
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ExpenseClaimsPage(
            claims: ExpenseClaims(
              companyId: 'company',
              claims: [expenseFixture('p')],
            ),
            onApprove: (_) {
              calls++;
              return response.future;
            },
          ),
        ),
      );
      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, '承認'),
      );
      button.onPressed!();
      button.onPressed!();
      await tester.pump();
      expect(calls, 1);
      response.completeError(StateError('synthetic'));
      await tester.pumpAndSettle();
      expect(find.textContaining('未承認 /'), findsOneWidget);
      expect(find.textContaining('更新結果を確認できません'), findsOneWidget);
    },
  );
  testWidgets(
    'compact view preserves long descriptions and status with no overflow',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: ExpenseClaimsPage(
            claims: ExpenseClaims(
              companyId: 'company',
              claims: [
                expenseFixture(
                  'long',
                  description: '長い経費内容を省略せず表示します。' * 10,
                ).reject(),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('却下 /'), findsOneWidget);
    },
  );
  testWidgets(
    'old company callbacks cannot act after authoritative data changes',
    (tester) async {
      var calls = 0;
      Future<void> approve(ExpenseClaim _) async {
        calls++;
      }

      await tester.pumpWidget(
        MaterialApp(
          home: ExpenseClaimsPage(
            claims: ExpenseClaims(
              companyId: 'company',
              claims: [expenseFixture('old')],
            ),
            onApprove: approve,
          ),
        ),
      );
      final oldAction = tester
          .widget<TextButton>(find.widgetWithText(TextButton, '承認'))
          .onPressed!;
      await tester.pumpWidget(
        MaterialApp(
          home: ExpenseClaimsPage(
            claims: ExpenseClaims(
              companyId: 'other',
              claims: [expenseFixture('new', company: 'other')],
            ),
            onApprove: approve,
          ),
        ),
      );
      oldAction();
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.byKey(const ValueKey('new')), findsOneWidget);
    },
  );
}
