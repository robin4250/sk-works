import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/payroll_fixed_deductions.dart';
import 'package:sk_works/features/payroll/payroll_insurance_settings_entry.dart';

void main() {
  for (final state in ['saved', 'missing', 'failed']) {
    testWidgets('one external entry retains status, applicable month and reference across all units: $state', (t) async {
      final controller = PayrollInsuranceEntryController();
      var showAmounts = false, hideDeductions = true;
      var reads = 0, opens = 0, average = 320000;
      String? openedMonth;
      Map<String, dynamic> response(bool full) => {'company_id': 'company', 'worker_id': 'worker',
        'can_edit': true, 'insurance_basis_reference_contract_version': 1,
        'items': state == 'missing' ? [] : [{'starts_on': '2026-09-01', 'version': 1, 'value': {
          'insurance_mode': 'rates', if (full) 'insurance_basis_reference': {
            'schema': 1, 'from': '2026-04-01', 'to': '2026-06-01',
            'average_monthly_income_yen': average, 'source': 'manual',
            'observed_months': 0, 'history_fingerprint': null,
          },
        }}]};
      Widget page() => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: Column(children: [
        PayrollInsuranceSettingsEntry(controller: controller),
        Offstage(offstage: hideDeductions, child: PayrollFixedDeductions(
          key: const ValueKey('stable-fixed-state'),
          companyId: 'company', workerId: 'worker', month: '2026-10-01',
          canEdit: true, showAmounts: showAmounts, entryController: controller,
          readStatement: (_, __, ___) async => {'calculation_blocked': false,
            'detail': {'tax_calculation': {'condition_version': 1,
              'conditions_start': '2026-09-01', 'premiums': {'健康保険料': 1000, '厚生年金保険': 2000}}}},
          openConditions: (month) async { opens++; openedMonth = month; average = 330000; },
          rpc: (name, params) async {
            if (name == 'payroll_deduction_overrides_contract_version') return 1;
            reads++; if (state == 'failed') throw StateError('unavailable');
            return response(name.endsWith('_with_insurance_reference'));
          },
        )),
      ]))));
      await t.pumpWidget(page()); await t.pumpAndSettle();
      final button = find.byKey(const ValueKey('insurance-settings-open'));
      expect(find.text('保険料を設定'), findsOneWidget);
      expect(find.ancestor(of: button, matching: find.byType(Card)), findsNothing);
      expect(find.text(state == 'saved' ? '設定済み（2026-10に適用）'
          : state == 'missing' ? '未設定（この月に適用する設定なし）'
          : '設定状況を確認できません'), findsOneWidget);
      if (state == 'saved') {
        expect(find.text('適用開始：2026-09'), findsOneWidget);
        expect(find.textContaining('2026-04〜2026-06・平均月収 320000円'), findsOneWidget);
      }
      final before = reads;
      hideDeductions = false;
      for (final monthly in [false, true, false]) {
        showAmounts = monthly;
        await t.pumpWidget(page()); await t.pumpAndSettle();
        expect(find.text('保険料を設定'), findsOneWidget);
        expect(reads, before, reason: 'unit view changes do not read or charge insurance again');
        if (state == 'saved') expect(find.text('適用開始：2026-09'), findsOneWidget);
      }
      await t.ensureVisible(button); await t.pumpAndSettle();
      await t.tap(button); await t.pumpAndSettle();
      expect(opens, 1); expect(openedMonth, '2026-10-01');
      expect(reads, greaterThan(before));
      if (state == 'saved') expect(find.textContaining('平均月収 330000円'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink()); await t.pump(); controller.dispose();
    });
  }
  testWidgets('external entry cannot discard an unsaved deduction correction', (t) async {
    final controller = PayrollInsuranceEntryController(); var opens = 0;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: Column(children: [
      PayrollInsuranceSettingsEntry(controller: controller),
      PayrollFixedDeductions(companyId: 'company', workerId: 'worker', month: '2026-10-01',
        canEdit: true, entryController: controller, openConditions: (_) async { opens++; },
        rpc: (name, params) async => name == 'payroll_deduction_overrides_contract_version' ? 1 : {
          'company_id': 'company', 'worker_id': 'worker', 'can_edit': true,
          'items': [{'starts_on': '2026-10-01', 'version': 1, 'value': {'insurance_mode': 'rates'}}]},
        readStatement: (_, __, ___) async => {'calculation_blocked': false, 'detail': {'tax_calculation': {
          'condition_version': 1, 'conditions_start': '2026-10-01', 'premiums': {'健康保険料': 1000}}}},
      ),
    ])))));
    await t.pumpAndSettle();
    final health = find.byKey(const ValueKey('fixed-deduction-health_insurance-amount'));
    await t.ensureVisible(health); await t.pumpAndSettle();
    await t.enterText(health, '1200'); t.testTextInput.hide(); await t.pumpAndSettle();
    final button = find.byKey(const ValueKey('insurance-settings-open'));
    await t.ensureVisible(button); await t.pumpAndSettle();
    expect(t.widget<FilledButton>(button).onPressed, isNull);
    await controller.open(); expect(opens, 0);
    expect(t.widget<TextFormField>(health).controller!.text, '1200');
    await t.pumpWidget(const SizedBox.shrink()); await t.pump(); controller.dispose();
  });
  test('a detached or stale owner cannot publish readiness for another worker', () async {
    final controller = PayrollInsuranceEntryController(); final old = Object(), current = Object();
    var oldOpens = 0, newOpens = 0;
    controller.attach(old, () async { oldOpens++; });
    controller.publish(old, const PayrollInsuranceEntryState(canOpen: true, status: 'old'));
    controller.detach(old); await controller.open(); expect(oldOpens, 0);
    controller.attach(current, () async { newOpens++; });
    controller.publish(current, const PayrollInsuranceEntryState(canOpen: true, status: 'current'));
    controller.publish(old, const PayrollInsuranceEntryState(canOpen: false, status: 'late old'));
    expect(controller.value.status, 'current'); await controller.open(); expect(newOpens, 1);
    controller.dispose(); await controller.open(); expect(newOpens, 1);
  });
}
