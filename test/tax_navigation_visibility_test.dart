import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/home/company_payroll_rates_home_entry.dart';
import 'package:sk_works/features/settings/company_income_tax_page.dart';
import 'package:sk_works/features/settings/company_payroll_rates_page.dart';

import 'features/settings/company_income_tax_page_test.dart'
    show FakeIncomeTaxRepository;
import 'features/settings/company_payroll_rates_page_test.dart'
    show FakeRatesRepository;

void main() {
  for (final scenario in ['rates', 'income', 'company-error']) {
    testWidgets('$scenario remains navigable after TOP hides its toolbar', (
      tester,
    ) async {
      final rates = FakeRatesRepository();
      final Widget page = switch (scenario) {
        'rates' => CompanyPayrollRatesPage(
          companyId: 'test-company',
          repository: rates,
          pendingStore: rates.pendingStore,
        ),
        'income' => CompanyIncomeTaxPage(
          companyId: 'test-company',
          repository: FakeIncomeTaxRepository(),
        ),
        _ => CompanyPayrollRatesHomePage(
          resolveCompanyId: () async => throw StateError('offline'),
        ),
      };
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(appBarTheme: const AppBarTheme(toolbarHeight: 0)),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => page),
                ),
                child: const Text('Open tax page'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open tax page'));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(AppBar)).height, greaterThanOrEqualTo(56));
      final back = find.byType(BackButton).hitTestable();
      expect(back, findsOneWidget);
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(find.text('Open tax page'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
