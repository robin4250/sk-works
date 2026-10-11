import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/expenses/expense_claim.dart';
import 'package:sk_works/features/expenses/expense_claims_page.dart';
import 'package:sk_works/features/help/menu_help_catalog.dart';
import 'package:sk_works/features/help/manual_content.dart';
import 'expense_fixture.dart';

Future<void> reveal(WidgetTester tester, Finder target) async {
  tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position
      .jumpTo(0);
  await tester.pump();
  await tester.scrollUntilVisible(
    target,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

void main() {
  test('expense help is reachable from the existing home feature key', () {
    final entries = MenuHelpCatalog.visibleFor(
      role: ManualRole.general,
      visibleKeys: const {'expense_claims'},
    );
    expect(entries, hasLength(1));
    expect(entries.single.key, 'expense_claims');
    expect(entries.single.details, contains('確認して保存'));
  });

  testWidgets(
    'all history, readable status and applicant link retain ID scope',
    (tester) async {
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
      await reveal(tester, find.byKey(const ValueKey('p')));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('p')),
          matching: find.text('未承認'),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '承認').first)
            .onPressed,
        isNull,
      );
      await reveal(tester, find.byKey(const ValueKey('r')));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('r')),
          matching: find.text('却下'),
        ),
        findsOneWidget,
      );
      await reveal(tester, find.text('別の社員'));
      await tester.tap(find.text('別の社員'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('a')), findsOneWidget);
      expect(find.byKey(const ValueKey('p')), findsNothing);
      expect(find.byKey(const ValueKey('r')), findsNothing);
    },
  );

  testWidgets(
    'callback pending blocks duplicates and failure never approves locally',
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
      await tester.pumpAndSettle();
      await reveal(tester, find.widgetWithText(TextButton, '承認'));
      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, '承認'),
      );
      button.onPressed!();
      button.onPressed!();
      await tester.pump();
      expect(calls, 1);
      response.completeError(StateError('synthetic'));
      await tester.pumpAndSettle();
      expect(find.text('未承認'), findsOneWidget);
      expect(find.textContaining('更新結果を確認できません'), findsOneWidget);
    },
  );

  testWidgets(
    'status and destination filters combine without counting rejected money',
    (tester) async {
      final customer = ExpenseAllocation(
        ExpenseCategory.customer,
        counterpartyId: 'customer',
        counterpartyName: '取引会社A',
      );
      final claims = ExpenseClaims(
        companyId: 'company',
        claims: [
          expenseFixture('p'),
          expenseFixture('a').approve().allocate(customer),
          expenseFixture('r').approve().allocate(customer).reject(),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(home: ExpenseClaimsPage(claims: claims)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '取引会社（2）'));
      await tester.tap(find.widgetWithText(ChoiceChip, '承認済み'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('a')), findsOneWidget);
      expect(find.byKey(const ValueKey('p')), findsNothing);
      expect(find.byKey(const ValueKey('r')), findsNothing);
      final amount = claims.entries.singleWhere((c) => c.id == 'a').amountYen;
      expect(find.text('表示：1件 / この負担先の承認済み：1件・$amount円'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, '却下'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('r')), findsOneWidget);
      expect(find.byKey(const ValueKey('a')), findsNothing);
    },
  );

  testWidgets(
    'allocation requires category, registered company and explicit save; cancel never writes',
    (tester) async {
      final destinations = [
        ExpenseAllocation(ExpenseCategory.ownCompany),
        ExpenseAllocation(
          ExpenseCategory.customer,
          counterpartyId: 'customer-a',
          counterpartyName: '取引会社A',
        ),
        ExpenseAllocation(
          ExpenseCategory.customer,
          counterpartyId: 'customer-b',
          counterpartyName: '取引会社B',
        ),
        ExpenseAllocation(
          ExpenseCategory.subcontractor,
          counterpartyId: 'partner-a',
          counterpartyName: '下請け会社A',
        ),
      ];
      final sent = <ExpenseAllocation>[];
      await tester.pumpWidget(
        MaterialApp(
          home: ExpenseClaimsPage(
            claims: ExpenseClaims(
              companyId: 'company',
              claims: [expenseFixture('a').approve()],
            ),
            destinations: destinations,
            onAllocate: (_, d) async => sent.add(d),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await reveal(tester, find.widgetWithText(OutlinedButton, '振り分け'));
      await tester.tap(find.widgetWithText(OutlinedButton, '振り分け'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '確認して保存'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byType(DropdownButtonFormField<ExpenseCategory>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取引会社').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '確認して保存'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取引会社B').last);
      await tester.pumpAndSettle();
      expect(find.text('変更後：取引会社 / 取引会社B'), findsOneWidget);
      expect(find.text('経費明細の表示先：取引会社の請求書'), findsOneWidget);
      expect(sent, isEmpty);
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      expect(sent, isEmpty);
      await tester.tap(find.widgetWithText(OutlinedButton, '振り分け'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<ExpenseCategory>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('自社').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('確認して保存'));
      await tester.pumpAndSettle();
      expect(sent.single.category, ExpenseCategory.ownCompany);
      expect(find.text('費用の負担先：自社'), findsOneWidget);
    },
  );

  testWidgets(
    'an open allocation confirmation cannot write after company data changes',
    (tester) async {
      final data = ValueNotifier(
        ExpenseClaims(
          companyId: 'company',
          claims: [expenseFixture('old').approve()],
        ),
      );
      addTearDown(data.dispose);
      var calls = 0;
      final destinations = [ExpenseAllocation(ExpenseCategory.ownCompany)];
      Future<void> allocate(
        ExpenseClaim claim,
        ExpenseAllocation destination,
      ) async {
        calls++;
      }

      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<ExpenseClaims>(
            valueListenable: data,
            builder: (context, claims, _) => ExpenseClaimsPage(
              claims: claims,
              destinations: destinations,
              onAllocate: allocate,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await reveal(tester, find.widgetWithText(OutlinedButton, '振り分け'));
      await tester.tap(find.widgetWithText(OutlinedButton, '振り分け'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<ExpenseCategory>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('自社').last);
      await tester.pumpAndSettle();
      data.value = ExpenseClaims(
        companyId: 'other',
        claims: [expenseFixture('new', company: 'other').approve()],
      );
      await tester.pump();
      await tester.tap(find.text('確認して保存'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      await reveal(tester, find.byKey(const ValueKey('new')));
      expect(find.byKey(const ValueKey('old')), findsNothing);
    },
  );

  testWidgets(
    '320 pixel view with large text scrolls through header and long claim; help opens',
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
      await reveal(tester, find.widgetWithText(TextButton, '承認'));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('経費の承認・振り分けのヘルプ'));
      await tester.pumpAndSettle();
      expect(find.textContaining('確定済み帳票は変更しません'), findsOneWidget);
      await tester.tap(find.text('閉じる'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'old company callback cannot write after authoritative data changes',
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
      await tester.pumpAndSettle();
      await reveal(tester, find.widgetWithText(TextButton, '承認'));
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
      await reveal(tester, find.byKey(const ValueKey('new')));
      expect(find.byKey(const ValueKey('new')), findsOneWidget);
    },
  );
}
