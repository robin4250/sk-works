import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/payroll_tax_conditions_page.dart';

void main() {
  final original = <String, dynamic>{'insurance_mode': 'rates', 'income_mode': 'fixed',
    'health': true, 'pension': true, 'employment': false, 'nursing': false, 'child_support': false,
    'birth_date': null, 'health_base_yen': 300000, 'pension_base_yen': 320000,
    'dependents': 0, 'non_taxable_yen': 0, 'employment_excluded_yen': 0,
    'additional_social_deduction_yen': 0};

  Future<void> enter(WidgetTester t, String key, String value) async {
    final field = find.byKey(ValueKey(key));
    await t.ensureVisible(field); await t.pumpAndSettle();
    await t.enterText(field, value); await t.pump();
  }

  Future<void> save(WidgetTester t) async {
    final button = find.widgetWithText(FilledButton, '確認して保存');
    await t.scrollUntilVisible(button, 400, scrollable: find.byType(Scrollable).first);
    await t.ensureVisible(button); await t.pumpAndSettle();
    await t.tap(button); await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, '確認して保存').last);
    await t.pumpAndSettle();
  }

  Future<void> scenario(WidgetTester t, {required bool supported, bool editIncome = true, bool manualOverride = false}) async {
    var version = 1;
    var saved = Map<String, dynamic>.from(original);
    Map<String, dynamic> response() => {'company_id': 'company', 'worker_id': 'worker',
      'can_edit': true, if (supported) 'insurance_basis_reference_contract_version': 1,
      'items': [{'starts_on': '2026-10-01', 'version': version, 'value': saved}]};
    await t.pumpWidget(MaterialApp(home: PayrollTaxConditionsPage(
      companyId: 'company', workerId: 'worker', month: DateTime(2026, 10),
      rpc: (name, params) async {
        if (name == 'read_worker_payroll_tax_conditions' ||
            name == 'read_worker_payroll_tax_conditions_with_insurance_reference') {
          return response();
        }
        if (name == 'read_worker_payroll_insurance_income_history') {
          return {'contract_version': 1, 'company_id': 'company', 'worker_id': 'worker',
            'from': params['p_from'], 'to': params['p_to'], 'items': [],
            'history_fingerprint': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'};
        }
        expect(name, 'save_worker_payroll_tax_conditions');
        expect(params['p_expected_version'], version);
        saved = Map<String, dynamic>.from(params['p_value'] as Map);
        version++;
        return response();
      },
    )));
    await t.pumpAndSettle();
    if (!editIncome) {
      await save(t);
      expect(saved['health_base_yen'], 300000);
      expect(saved['pension_base_yen'], 320000);
      expect(saved.containsKey('insurance_basis_reference'), isFalse);
      await t.pumpWidget(const SizedBox.shrink()); await t.pump();
      return;
    }
    await enter(t, 'insurance-reference-from', '2026-07');
    await enter(t, 'insurance-reference-to', '2026-09');
    await enter(t, 'insurance-reference-average', '480000');
    if (manualOverride) {
      final tile = find.byKey(const ValueKey('insurance-standard-base-overrides'));
      await t.ensureVisible(tile); await t.pumpAndSettle();
      await t.tap(find.descendant(of: tile, matching: find.text('通知書の金額で手動修正')));
      await t.pumpAndSettle();
      final health = find.widgetWithText(TextFormField, '健康保険の標準報酬月額（円）');
      await t.ensureVisible(health); await t.pumpAndSettle();
      await t.enterText(health, '440000'); await t.pump();
    }
    await save(t);
    expect(saved['health_base_yen'], manualOverride ? 440000 : 470000);
    expect(saved['pension_base_yen'], 470000);
    expect(saved['income_mode'], 'fixed');
    if (supported) {
      expect(saved['insurance_basis_reference'], {'schema': 1, 'from': '2026-07-01',
        'to': '2026-09-01', 'average_monthly_income_yen': 480000,
        'source': 'manual', 'observed_months': 0, 'history_fingerprint': null});
      final reload = find.widgetWithText(TextButton, '再読み込み');
      await t.ensureVisible(reload); await t.pumpAndSettle();
      await t.tap(reload); await t.pumpAndSettle();
      final field = t.widget<TextFormField>(find.byKey(const ValueKey('insurance-reference-average')));
      expect(field.controller!.text, '480000');
      expect(t.widget<TextFormField>(find.byKey(const ValueKey('insurance-reference-from'))).controller!.text, '2026-07');
    } else {
      expect(saved.containsKey('insurance_basis_reference'), isFalse);
      expect(find.textContaining('対象期間・平均月収は未保存です。'), findsWidgets);
    }
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump();
  }

  testWidgets('single income input saves and reloads both derived standard bases',
      (t) => scenario(t, supported: true));
  testWidgets('opening and saving does not overwrite existing different bases',
      (t) => scenario(t, supported: true, editIncome: false));
  testWidgets('notice amount override is saved instead of the derived health base',
      (t) => scenario(t, supported: true, manualOverride: true));
  testWidgets('unprepared server preserves normal condition save and discloses unsaved reference',
      (t) => scenario(t, supported: false));

  testWidgets('invalid average and reversed period never call the save RPC', (t) async {
    var saves = 0;
    await t.pumpWidget(MaterialApp(home: PayrollTaxConditionsPage(companyId: 'company',
      workerId: 'worker', month: DateTime(2026, 10), rpc: (name, params) async {
        if (name == 'save_worker_payroll_tax_conditions') saves++;
        return {'company_id': 'company', 'worker_id': 'worker', 'can_edit': true,
          'items': [{'starts_on': '2026-10-01', 'version': 1, 'value': original}]};
      })));
    await t.pumpAndSettle();
    await enter(t, 'insurance-reference-average', '1.5');
    final saveButton = find.widgetWithText(FilledButton, '確認して保存');
    await t.scrollUntilVisible(saveButton, 400, scrollable: find.byType(Scrollable).first);
    await t.ensureVisible(saveButton); await t.pumpAndSettle(); await t.tap(saveButton); await t.pumpAndSettle();
    expect(saves, 0); expect(find.byType(AlertDialog), findsNothing);
    await enter(t, 'insurance-reference-average', '300000');
    await enter(t, 'insurance-reference-from', '2026-11');
    await t.ensureVisible(saveButton); await t.pumpAndSettle(); await t.tap(saveButton); await t.pumpAndSettle();
    expect(saves, 0); expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('declared full-reader failure does not enable saving partial conditions', (t) async {
    final calls = <String>[];
    await t.pumpWidget(MaterialApp(home: PayrollTaxConditionsPage(companyId: 'company',
      workerId: 'worker', month: DateTime(2026, 10), rpc: (name, params) async {
        calls.add(name);
        if (name.endsWith('_with_insurance_reference')) throw StateError('denied');
        return {'company_id': 'company', 'worker_id': 'worker', 'can_edit': true,
          'insurance_basis_reference_contract_version': 1,
          'items': [{'starts_on': '2026-10-01', 'version': 1, 'value': original}]};
      })));
    await t.pumpAndSettle();
    expect(calls, ['read_worker_payroll_tax_conditions',
      'read_worker_payroll_tax_conditions_with_insurance_reference']);
    expect(find.widgetWithText(FilledButton, '確認して保存'), findsNothing);
    expect(find.textContaining('税計算条件を取得できません'), findsOneWidget);
  });
}
