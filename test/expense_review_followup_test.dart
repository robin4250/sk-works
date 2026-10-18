import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sk_works/features/expenses/expense_claim.dart';
import 'package:sk_works/features/expenses/expense_claims_page.dart';
import 'package:sk_works/features/expenses/expense_review_flow_dialog.dart';
import 'package:sk_works/features/expenses/expense_settlement_choice.dart';
import 'package:sk_works/features/expenses/expense_settlement_dialog.dart';

ExpenseClaim claim(String id, DateTime submitted, {DateTime? incurred}) =>
    ExpenseClaim(
      id: id,
      companyId: 'company',
      applicantId: 'worker',
      applicantName: 'Fixture',
      incurredOn: incurred ?? DateTime(2026, 10, 1),
      submittedAt: submitted,
      description: id,
      amountYen: 100,
      approval: ExpenseApproval.pending,
      allocation: ExpenseAllocation(ExpenseCategory.unallocated),
    );
final fixture = claim('claim', DateTime.utc(2026, 10, 1));

Future<void> tap(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).last);
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

Future<void> open(
  WidgetTester tester,
  List<ExpenseAllocation> companies,
  void Function(ExpenseReviewDecision?) receive,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              receive(
                await showDialog<ExpenseReviewDecision>(
                  context: context,
                  builder: (_) => ExpenseReviewFlowDialog(
                    claim: fixture,
                    destinations: companies,
                  ),
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tap(tester, 'Open');
  await tap(tester, '次へ');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'newest submission comes first regardless of use date without mutating source',
    (tester) async {
      tester.view.physicalSize = const Size(900, 3500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final claims = ExpenseClaims(
        companyId: 'company',
        claims: [
          claim(
            'old',
            DateTime.utc(2026, 10, 1),
            incurred: DateTime(2026, 10, 30),
          ),
          claim(
            'new',
            DateTime.utc(2026, 10, 19),
            incurred: DateTime(2026, 9, 1),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(home: ExpenseClaimsPage(claims: claims)),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('new'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const ValueKey('old'))).dy),
      );
      expect(claims.entries.map((c) => c.id), ['old', 'new']);
    },
  );

  for (final category in [
    ExpenseCategory.subcontractor,
    ExpenseCategory.customer,
  ]) {
    testWidgets(
      'external $category uses separate company picker and allows payroll',
      (tester) async {
        ExpenseReviewDecision? result;
        final company = ExpenseAllocation(
          category,
          counterpartyId: 'external',
          counterpartyName: 'Selected company',
        );
        final wrong = ExpenseAllocation(
          category == ExpenseCategory.customer
              ? ExpenseCategory.subcontractor
              : ExpenseCategory.customer,
          counterpartyId: 'wrong',
          counterpartyName: 'Wrong category company',
        );
        await open(tester, [company, wrong], (value) => result = value);
        await tap(tester, expenseBurdenLabel(category));
        expect(find.byType(SimpleDialog), findsOneWidget);
        expect(find.text('Wrong category company'), findsNothing);
        await tap(tester, 'Selected company');
        expect(find.byType(SimpleDialog), findsNothing);
        await tap(tester, '次へ');
        expect(find.text('給与精算'), findsOneWidget);
        expect(find.text('現金精算'), findsOneWidget);
        expect(find.text('支払済み（対象外）'), findsOneWidget);
        expect(find.text('立替精算'), findsNothing);
        await tap(tester, '給与精算');
        await tap(tester, '次へ');
        await tap(tester, '次へ');
        expect(result, isNull);
        await tap(tester, '確定');
        expect(result!.destination!.counterpartyId, 'external');
        expect(result!.destination!.category, category);
        expect(result!.settlement!.method, ExpenseSettlementMethod.payroll);
        expect(tester.takeException(), isNull);
      },
    );


  }

  testWidgets(
    'changing from own company clears the previously chosen payroll method',
    (tester) async {
      await open(tester, [
        ExpenseAllocation(
          ExpenseCategory.customer,
          counterpartyId: 'external',
          counterpartyName: 'External',
        ),
      ], (_) {});
      await tap(tester, '自社');
      await tap(tester, '次へ');
      await tap(tester, '給与精算');
      await tap(tester, '戻る');
      await tap(tester, '取引会社');
      await tap(tester, 'External');
      await tap(tester, '次へ');
      expect(find.text('給与精算'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '次へ'))
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets('cancelled or empty company selection cannot advance or save', (
    tester,
  ) async {
    ExpenseReviewDecision? result;
    await open(tester, [], (value) => result = value);
    await tap(tester, '下請け会社');
    expect(find.textContaining('登録済みの会社がありません'), findsOneWidget);
    await tap(tester, '戻る');
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '次へ'))
          .onPressed,
      isNull,
    );
    await tap(tester, 'キャンセル');
    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });
  for (final category in [
    ExpenseCategory.subcontractor,
    ExpenseCategory.customer,
  ]) {
    testWidgets(
      'legacy setup for $category shows three methods and explains unavailable paid',
      (tester) async {
        final external = ExpenseClaim(
          id: 'external',
          companyId: 'company',
          applicantId: 'worker',
          applicantName: 'Fixture',
          incurredOn: DateTime(2026, 10, 1),
          submittedAt: DateTime.utc(2026, 10, 1),
          description: 'External expense',
          amountYen: 100,
          approval: ExpenseApproval.approved,
          allocation: ExpenseAllocation(category, counterpartyId: 'registered'),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: ExpenseSettlementDialog(claim: external)),
          ),
        );
        expect(find.text('給与精算'), findsOneWidget);
        expect(find.text('支払済み（対象外）'), findsOneWidget);
        expect(find.text('立替精算'), findsNothing);
        expect(tester.widget<ListTile>(find.widgetWithText(ListTile, '支払済み（対象外）')).onTap, isNull);
        expect(find.text('承認・振り分け機能の更新後に利用できます。'), findsOneWidget);
        expect(find.text('現金精算'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, '承認して保存'))
              .onPressed,
          isNull,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
