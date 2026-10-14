import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/home/company_payroll_rates_home_entry.dart';
import 'package:sk_works/features/expenses/expense_home_page.dart';
import 'package:sk_works/features/home/friendly_home_content.dart';
import 'package:sk_works/features/home/home_attention_repository.dart';
import 'package:sk_works/features/home/home_membership_repository.dart';
import 'package:sk_works/features/settings/company_payroll_rates_page.dart';

void main() {
  Widget home(String role) => MaterialApp(
    home: Scaffold(
      body: Builder(builder: (testContext) => FriendlyHomeContent(
        identity: HomeIdentity(
          role: role,
          companyName: 'Test',
          displayName: 'Test',
        ),
        requiredDocumentAttention: const RequiredDocumentAttention(
          missingCount: 0,
          missingNames: [],
          needsLicense: false,
          needsQualification: false,
        ),
        moduleEnabled: (_) => false,
        visibleHomeKeys: const {'payroll', 'expense_claims'},
        shortcuts: [
          const HomeShortcut('payroll', '給与明細', Icons.payments_outlined),
          const HomeShortcut('expense_claims', '経費', Icons.receipt_long_outlined),
        ],
        showAttendanceReport: false,
        showTodayAttendance: false,
        onOpen: (key) async {
          if (key == 'company_tax_rates') {
            await Navigator.of(testContext).push<void>(MaterialPageRoute(builder: (_) => const CompanyPayrollRatesHomePage()));
          } else if (key == 'expense_claims') {
            await Navigator.of(testContext).push<void>(MaterialPageRoute(builder: (_) => const ExpenseHomePage()));
          }
        },
        onRefresh: () async {},
      )),
    ),
  );

  for (final role in ['viewer', 'admin', 'owner']) {
    testWidgets('$role has no standalone tax shortcut on TOP', (tester) async {
      await tester.pumpWidget(home(role));
      expect(find.text('税率設定'), findsNothing);
      final grid = tester.widget<GridView>(find.byType(GridView));
      final tiles = (grid.childrenDelegate as SliverChildListDelegate).children;
      expect(tiles, hasLength(2));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('member opens expense submission and review choices from TOP', (tester) async {
    await tester.pumpWidget(home('member'));
    await tester.tap(find.text('経費'));
    await tester.pumpAndSettle();
    expect(find.byType(ExpenseHomePage), findsOneWidget);
    expect(find.text('自分の経費申請'), findsOneWidget);
    expect(find.text('全員の申請・振り分け'), findsOneWidget);
    await tester.pageBack(); await tester.pumpAndSettle();
    expect(find.byType(FriendlyHomeContent), findsOneWidget);
  });

  for (final role in ['member', 'manager']) {
    testWidgets('$role retains existing tax access scope', (tester) async {
      await tester.pumpWidget(home(role));
      expect(find.text('税率設定'), findsNothing);
    });
  }

  testWidgets(
    'resolved membership opens the existing tax page for that company',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CompanyPayrollRatesHomePage(
            resolveCompanyId: () async => 'resolved-company',
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(
        tester
            .widget<CompanyPayrollRatesPage>(
              find.byType(CompanyPayrollRatesPage),
            )
            .companyId,
        'resolved-company',
      );
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'company lookup failure retries and completion after pop is safe',
    (tester) async {
      var calls = 0;
      final pending = Completer<String>();
      await tester.pumpWidget(
        MaterialApp(
          home: CompanyPayrollRatesHomePage(
            resolveCompanyId: () {
              calls++;
              if (calls == 1) return Future.error(StateError('offline'));
              return pending.future;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('会社情報を読み込めませんでした。'), findsOneWidget);
      await tester.tap(find.text('再試行'));
      await tester.pump();
      expect(calls, 2);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      pending.complete('company-test');
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
