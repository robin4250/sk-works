import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/payroll_review_page.dart';
import 'package:sk_works/features/home/company_payroll_rates_home_entry.dart';

void main() {
  testWidgets('payroll list has equal-width entries and opens the existing tax page', (t) async {
    t.view.physicalSize = const Size(320, 720);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    var individual = 0;
    await t.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
        child: child!,
      ),
      home: Builder(builder: (context) => PayrollReviewPage(
        onOpenSettings: () { individual++; },
        onOpenTaxRates: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const CompanyPayrollRatesHomePage()),
        ),
      )),
    ));
    await t.pumpAndSettle();
    final tax = find.byKey(const ValueKey('payroll-tax-rates-entry'));
    final settings = find.byKey(const ValueKey('payroll-individual-settings-entry'));
    expect(t.getSize(tax), t.getSize(settings));
    expect(t.getTopLeft(tax).dy, t.getTopLeft(settings).dy);
    expect(t.getTopLeft(tax).dx, lessThan(t.getTopLeft(settings).dx));
    expect(find.text('個別給料設定'), findsOneWidget);
    await t.tap(settings);
    expect(individual, 1);
    await t.tap(tax);
    await t.pumpAndSettle();
    expect(find.byType(CompanyPayrollRatesHomePage), findsOneWidget);
    expect(find.text('再試行'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.byType(PayrollReviewPage), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('an unavailable permission keeps the corresponding entry disabled', (t) async {
    await t.pumpWidget(MaterialApp(home: PayrollReviewPage(onOpenSettings: () {})));
    await t.pumpAndSettle();
    expect(t.widget<OutlinedButton>(find.byKey(const ValueKey('payroll-tax-rates-entry'))).onPressed, isNull);
    expect(t.widget<OutlinedButton>(find.byKey(const ValueKey('payroll-individual-settings-entry'))).onPressed, isNotNull);
    expect(t.takeException(), isNull);
  });

  test('the tax route is nested under payroll with its original role restriction', () {
    final app = File('lib/app_v2.dart').readAsStringSync();
    expect(app, contains("onOpenTaxRates: (_identity.isAdmin || _isViewer)"));
    expect(app, contains("onOpenSettings: (_identity.isAdmin || _isViewer)"));
    expect(app, contains("if (!_nestedActionKeys.contains('company_tax_rates')) return"));
    expect(app, isNot(contains("_MenuAction(key: 'company_tax_rates'")));
    expect(app, contains("page = const CompanyPayrollRatesHomePage()"));
  });
}
