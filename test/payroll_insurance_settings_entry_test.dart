import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/payroll_fixed_deductions.dart';

void main() {
  for (final state in ['saved', 'missing', 'failed']) {
    testWidgets('insurance entry stays visible across unit views: $state', (t) async {
      var opens = 0, reads = 0;
      String? openedMonth;
      var amounts = false;
      Widget page() => MaterialApp(home: Scaffold(body: SingleChildScrollView(
        child: PayrollFixedDeductions(
          companyId: 'company', workerId: 'worker', month: '2026-10-01',
          canEdit: true, showAmounts: amounts,
          readStatement: (_, __, ___) async => null,
          openConditions: (month) async { opens++; openedMonth = month; },
          rpc: (name, params) async {
            if (name == 'payroll_deduction_overrides_contract_version') return 1;
            reads++;
            if (state == 'failed') throw StateError('read denied');
            return {'company_id': 'company', 'worker_id': 'worker', 'can_edit': true,
              'items': state == 'missing' ? [] : [
                {'starts_on': '2026-09-01', 'version': 1, 'value': {'insurance_mode': 'rates'}}
              ]};
          },
        ),
      )));
      await t.pumpWidget(page()); await t.pumpAndSettle();
      final entry = find.byKey(const ValueKey('insurance-settings-open'));
      expect(entry, findsOneWidget);
      expect(find.text('保険料を設定'), findsOneWidget);
      expect(find.byKey(const ValueKey('fixed-deduction-health_insurance-amount')), findsNothing);
      expect(find.text(state == 'saved' ? '設定済み（2026-10に適用）'
          : state == 'missing' ? '未設定（この月に適用する設定なし）'
          : '設定状況を確認できません'), findsOneWidget);
      await t.tap(entry); await t.pumpAndSettle();
      expect(opens, 1); expect(openedMonth, '2026-10-01');
      final afterOpen = reads;
      amounts = true;
      await t.pumpWidget(page()); await t.pumpAndSettle();
      expect(entry, findsOneWidget);
      expect(reads, afterOpen, reason: 'unit view change must retain the existing state');
      expect(find.byKey(const ValueKey('fixed-deduction-health_insurance-amount')), findsOneWidget);
      amounts = false;
      await t.pumpWidget(page()); await t.pumpAndSettle();
      expect(entry, findsOneWidget); expect(reads, afterOpen);
      await t.pumpWidget(const SizedBox.shrink()); await t.pump();
    });
  }
}
