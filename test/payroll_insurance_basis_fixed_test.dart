import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/payroll_fixed_deductions.dart';

void main() {
  final reference = {'schema': 1, 'from': '2026-07-01', 'to': '2026-09-01',
    'average_monthly_income_yen': 480000, 'source': 'manual', 'observed_months': 0,
    'history_fingerprint': null};
  for (final fullReadFails in [false, true]) {
    testWidgets('fixed frames use full metadata reader, failure=$fullReadFails', (t) async {
      final calls = <String>[];
      var statementReads = 0;
      await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
        child: PayrollFixedDeductions(companyId: 'company', workerId: 'worker',
          month: '2026-10-01', canEdit: true, openConditions: (_) async {},
          readStatement: (_, __, ___) async {
            statementReads++;
            return {'calculation_blocked': false, 'detail': {'tax_calculation': {
              'condition_version': 1, 'conditions_start': '2026-10-01',
              'premiums': {'健康保険料': 10000, '厚生年金保険': 20000},
            }}};
          },
          rpc: (name, params) async {
            calls.add(name);
            if (name == 'payroll_deduction_overrides_contract_version') return 1;
            if (name == 'payroll_tax_adjustment_reason_contract_version') return 1;
            if (name.endsWith('_with_insurance_reference') && fullReadFails) throw StateError('denied');
            return {'company_id': 'company', 'worker_id': 'worker', 'can_edit': true,
              'insurance_basis_reference_contract_version': 1,
              'items': [{'starts_on': '2026-10-01', 'version': 1, 'value': {
                'insurance_mode': 'rates',
                if (name.endsWith('_with_insurance_reference')) 'insurance_basis_reference': reference,
              }}]};
          },
        ),
      ))));
      await t.pumpAndSettle();
      expect(calls, ['payroll_deduction_overrides_contract_version', 'read_worker_payroll_tax_conditions',
        'read_worker_payroll_tax_conditions_with_insurance_reference',
        if (!fullReadFails) 'payroll_tax_adjustment_reason_contract_version']);
      if (fullReadFails) {
        expect(statementReads, 0);
        expect(find.textContaining('税・保険料の計算結果を取得できません'), findsOneWidget);
        expect(find.textContaining('平均月収 480000円'), findsNothing);
      } else {
        expect(statementReads, 1);
        expect(find.textContaining('平均月収 480000円'), findsOneWidget);
        expect(t.widget<TextFormField>(find.byKey(const ValueKey('fixed-deduction-health_insurance-amount'))).controller!.text, '10000');
      }
    });
  }
}
