import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/payroll_insurance_basis_reference.dart';
import 'package:sk_works/features/payroll/payroll_insurance_basis_section.dart';

void main() {
  const fingerprint = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const manual = PayrollInsuranceBasisReference(from: '2026-07-01', to: '2026-09-01',
    averageMonthlyIncomeYen: 480000, source: 'manual', observedMonths: 0);
  PayrollInsuranceIncomeHistory history(String from, String to) => PayrollInsuranceIncomeHistory(
    from: from, to: to, fingerprint: fingerprint, items: const [
      PayrollInsuranceIncomeMonth(statementId: 's1', month: '2026-07-01', grossPay: 300000, finalized: true, revision: 1),
      PayrollInsuranceIncomeMonth(statementId: 's2', month: '2026-08-01', grossPay: 310000, finalized: true, revision: 1),
      PayrollInsuranceIncomeMonth(statementId: 's3', month: '2026-09-01', grossPay: 320000, finalized: false, revision: 2),
    ]);
  Widget page(PayrollInsuranceBasisSection section) => MaterialApp(home: Scaffold(
    body: Form(child: ListView(children: [section]))));

  testWidgets('automatic candidate does not overwrite manual, selection then period change invalidates proof', (t) async {
    PayrollInsuranceBasisReference? changed;
    await t.pumpWidget(page(PayrollInsuranceBasisSection(month: '2026-10-01',
      supported: true, enabled: true, initialReference: manual,
      readHistory: (from, to) async => history(from, to), onChanged: (value) => changed = value)));
    await t.pumpAndSettle();
    final average = find.byKey(const ValueKey('insurance-reference-average'));
    expect(t.widget<TextFormField>(average).controller!.text, '480000');
    expect(changed, isNull);
    final details = find.byKey(const ValueKey('insurance-reference-details'));
    await t.ensureVisible(details); await t.pumpAndSettle();
    await t.tap(details); await t.pumpAndSettle();
    final use = find.byKey(const ValueKey('insurance-use-period-average'));
    await t.ensureVisible(use); await t.pumpAndSettle(); await t.tap(use); await t.pump();
    expect(changed!.source, 'actual_complete'); expect(changed!.historyFingerprint, fingerprint);
    await t.ensureVisible(average); await t.pumpAndSettle();
    await t.enterText(average, '490000'); await t.pump();
    expect(changed!.source, 'manual'); expect(changed!.historyFingerprint, isNull);
    await t.ensureVisible(use); await t.pumpAndSettle(); await t.tap(use); await t.pump();
    expect(changed!.source, 'actual_complete');
    final from = find.byKey(const ValueKey('insurance-reference-from'));
    await t.ensureVisible(from); await t.pumpAndSettle(); await t.enterText(from, '2026-06'); await t.pump();
    expect(changed, isNull);
    expect(t.widget<TextFormField>(average).controller!.text, isEmpty);
    await t.pumpWidget(const SizedBox.shrink()); await t.pump();
  });

  testWidgets('disposed scope ignores a late history response', (t) async {
    final old = Completer<PayrollInsuranceIncomeHistory>();
    var changed = 0;
    await t.pumpWidget(page(PayrollInsuranceBasisSection(key: const ValueKey('old-worker'),
      month: '2026-10-01', supported: true, enabled: true, initialReference: manual,
      readHistory: (_, __) => old.future, onChanged: (_) => changed++)));
    await t.pump();
    await t.pumpWidget(page(PayrollInsuranceBasisSection(key: const ValueKey('new-worker'),
      month: '2026-11-01', supported: false, enabled: true,
      readHistory: (from, to) async => history(from, to), onChanged: (_) => changed++)));
    await t.pump();
    old.complete(history('2026-07-01', '2026-09-01')); await t.pumpAndSettle();
    expect(changed, 0);
    expect(t.widget<TextFormField>(find.byKey(const ValueKey('insurance-reference-average'))).controller!.text, isEmpty);
    expect(find.textContaining('期間平均候補 310000円'), findsNothing);
  });
}
