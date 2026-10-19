import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/payroll_fixed_deductions.dart';

const month = '2026-10-01';
final initialProfile = <String, dynamic>{
  'insurance_mode': 'rates', 'income_mode': 'koh',
};

class _Backend {
  int version = 1, writes = 0;
  Map<String, dynamic> value = Map.of(initialProfile);
  Map<String, dynamic>? sent;
  bool edit = true, failSave = false;
  bool hasConditions = true;
  Map<String, dynamic> get response => {
    'company_id': 'company', 'worker_id': 'worker', 'can_edit': edit,
    'items': hasConditions
        ? [{'starts_on': month, 'version': version, 'value': value}] : [],
  };
  Future<dynamic> rpc(String name, Map<String, dynamic> params) async {
    if (name == 'payroll_deduction_overrides_contract_version') return 1;
    if (name == 'read_worker_payroll_tax_conditions') return response;
    expect(name, 'save_worker_payroll_tax_conditions');
    expect(params['p_company_id'], 'company');
    expect(params['p_worker_id'], 'worker');
    expect(params['p_starts_on'], month);
    expect(params['p_expected_version'], version);
    expect(params['p_confirmed'], isTrue);
    if (failSave) throw StateError('offline');
    sent = Map<String, dynamic>.from(params['p_value'] as Map);
    value = sent!;
    writes++;
    version++;
    return response;
  }
  Future<Map<String, dynamic>?> statement(String company, String worker, String period) async {
    expect([company, worker, period], ['company', 'worker', month]);
    final overrides = value['deduction_overrides'] as Map? ?? {};
    return {'calculation_blocked': false, 'detail': {'tax_calculation': {
      'condition_version': version, 'conditions_start': month,
      'income_tax_yen': overrides['income_tax'] ?? 1000,
      'automatic_income_tax_yen': 1000,
      'automatic_premiums': {
        '雇用保険料': 100, '健康保険料': 5000, '厚生年金保険': 9000, '介護保険料': 0,
      },
      'premiums': {
        '雇用保険料': overrides['employment_insurance'] ?? 100,
        '健康保険料': overrides['health_insurance'] ?? 5000,
        '厚生年金保険': overrides['pension_insurance'] ?? 9000,
        '介護保険料': overrides['nursing_insurance'] ?? 0,
      },
    }}};
  }
}

Finder amount(String key) => find.byKey(ValueKey('fixed-deduction-$key-amount'));
Finder card(String key) => find.byKey(ValueKey('fixed-deduction-$key'));
String? helper(WidgetTester t, String key) => t.widget<TextField>(
  find.descendant(of: amount(key), matching: find.byType(TextField)),
).decoration?.helperText;

Future<void> _mount(WidgetTester t, _Backend b, {
  PayrollDeductionStatementReader? reader,
  Future<void> Function()? rates,
  Future<void> Function(String month)? conditions,
}) async {
  await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
    child: PayrollFixedDeductions(
      companyId: 'company', workerId: 'worker', month: month,
      canEdit: b.edit, readStatement: reader ?? b.statement,
      rpc: b.rpc, openRates: rates, openConditions: conditions,
      legacySocialAmount: 12345,
      residentTax: const Text('登録済みの住民税'),
    ),
  ))));
  await t.pumpAndSettle();
}

Future<void> save(WidgetTester t) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await t.pumpAndSettle();
  final button = find.widgetWithText(FilledButton, '税・保険料を登録');
  await t.ensureVisible(button);
  await t.pumpAndSettle();
  expect(t.widget<FilledButton>(button).onPressed, isNotNull);
  await t.tap(button);
  await t.pumpAndSettle();
  await t.tap(find.text('確認して保存'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('disposed deduction panel stops before fetching conditions', (t) async {
    final contract = Completer<dynamic>();
    final calls = <String>[];
    await t.pumpWidget(MaterialApp(home: PayrollFixedDeductions(
      companyId: 'company', workerId: 'worker', month: month,
      residentTax: const SizedBox.shrink(),
      readStatement: (_, _, _) async => throw StateError('must not read'),
      rpc: (name, params) {
        calls.add(name);
        return contract.future;
      },
    )));
    await t.pumpWidget(const SizedBox.shrink());
    contract.complete(1);
    await t.pumpAndSettle();
    expect(calls, ['payroll_deduction_overrides_contract_version']);
    expect(t.takeException(), isNull);
  });

  testWidgets('failed refresh clears stale calculated amounts and keeps corrections', (t) async {
    final b = _Backend()..value = {
      ...initialProfile, 'deduction_overrides': {'income_tax': 1234},
    };
    var failRead = false;
    await _mount(t, b, reader: (company, worker, period) async {
      if (failRead) throw StateError('offline');
      return b.statement(company, worker, period);
    });
    expect(t.widget<TextFormField>(amount('health_insurance')).controller!.text, '5000');
    failRead = true;
    final reload = find.widgetWithText(TextButton, '税・保険料を再読み込み');
    await t.ensureVisible(reload);
    await t.tap(reload);
    await t.pumpAndSettle();
    expect(t.widget<TextFormField>(amount('health_insurance')).controller!.text, isEmpty);
    expect(helper(t, 'health_insurance'), '計算結果未確認');
    expect(t.widget<TextFormField>(amount('income_tax')).controller!.text, '1234');
    expect(t.widget<TextFormField>(amount('income_tax')).enabled, isFalse);
    expect(b.writes, 0);
    failRead = false;
    await t.tap(reload);
    await t.pumpAndSettle();
    expect(t.widget<TextFormField>(amount('health_insurance')).controller!.text, '5000');
    expect(helper(t, 'health_insurance'), '自動計算');
    expect(b.writes, 0);
  });

  testWidgets('returning from initial conditions reloads generated deductions', (t) async {
    final b = _Backend()..hasConditions = false;
    await _mount(t, b, conditions: (_) async { b.hasConditions = true; });
    final setup = find.widgetWithText(TextButton, '税・保険料の自動計算を設定');
    await t.ensureVisible(setup);
    await t.pumpAndSettle();
    await t.tap(setup);
    await t.pumpAndSettle();
    expect(setup, findsNothing);
    expect(helper(t, 'income_tax'), '自動計算');
    expect(t.widget<TextFormField>(amount('income_tax')).controller!.text, '1000');
    expect(b.writes, 0);
  });

  testWidgets('condition setup receives the same month as the deduction statement', (t) async {
    final b = _Backend()..hasConditions = false;
    String? inspected;
    await _mount(t, b, conditions: (month) async { inspected = month; });
    final setup = find.widgetWithText(TextButton, '税・保険料の自動計算を設定');
    await t.ensureVisible(setup);
    await t.pumpAndSettle();
    await t.tap(setup);
    await t.pumpAndSettle();
    expect(inspected, month);
    expect(b.writes, 0);
  });

  testWidgets('unset conditions are not described as waiting automatic calculation', (t) async {
    final b = _Backend()..hasConditions = false;
    await _mount(t, b);
    for (final item in fixedPayrollDeductions) {
      final field = t.widget<TextFormField>(amount(item.$1));
      expect(helper(t, item.$1), '計算条件未設定');
      expect(field.controller!.text, isEmpty);
      expect(field.enabled, isFalse);
    }
    expect(b.writes, 0);
  });

  testWidgets('fixed settings are not labelled automatic and manual corrections stay explicit', (t) async {
    final b = _Backend()..value = {
      'insurance_mode': 'fixed', 'income_mode': 'fixed',
      'deduction_overrides': {'income_tax': 1234},
    };
    await _mount(t, b);
    expect(helper(t, 'income_tax'),
        '手入力修正');
    for (final key in fixedPayrollDeductions.skip(1).map((i) => i.$1)) {
      expect(helper(t, key),
          '一括固定額設定（個別計算なし）');
    }
    final reset = find.descendant(of: card('income_tax'),
        matching: find.text('自動計算に戻す'));
    await t.tap(reset);
    await t.pumpAndSettle();
    expect(t.widget<TextFormField>(amount('income_tax')).controller!.text, '1000');
    expect(helper(t, 'income_tax'),
        '固定額設定');
    expect(b.writes, 0);
  });

  testWidgets('fixed order, generated amounts, explicit zero and restore automatic', (t) async {
    final b = _Backend();
    await _mount(t, b);
    final ordered = [...fixedPayrollDeductions.map((i) => i.$1), 'resident_tax'];
    for (var i = 1; i < ordered.length; i++) {
      expect(t.getTopLeft(card(ordered[i])).dy,
          greaterThan(t.getTopLeft(card(ordered[i - 1])).dy));
    }
    expect(find.text('社会保険・月額'), findsNothing);
    expect(t.widget<TextFormField>(amount('health_insurance')).controller!.text, '5000');
    expect(t.widget<TextFormField>(amount('nursing_insurance')).controller!.text, '0');
    expect(b.writes, 0);
    await t.ensureVisible(amount('health_insurance'));
    await t.enterText(amount('health_insurance'), '5100');
    await t.ensureVisible(amount('employment_insurance'));
    await t.enterText(amount('employment_insurance'), '0');
    await save(t);
    expect(b.sent!['deduction_overrides'], {
      'health_insurance': 5100, 'employment_insurance': 0,
    });
    expect(t.widget<TextFormField>(amount('health_insurance')).controller!.text, '5100');
    final reset = find.descendant(of: card('health_insurance'),
        matching: find.text('自動計算に戻す'));
    await t.ensureVisible(reset);
    await t.tap(reset);
    await t.pumpAndSettle();
    expect(t.widget<TextFormField>(amount('health_insurance')).controller!.text, '5000');
    await save(t);
    expect(b.sent!['deduction_overrides'], {'employment_insurance': 0});
    expect(b.writes, 2);
    expect(t.takeException(), isNull);
  });

  testWidgets('formula link opens actual rate settings and viewer cannot edit', (t) async {
    final b = _Backend()..edit = false;
    var opened = 0;
    await _mount(t, b, rates: () async { opened++; });
    expect(t.widget<TextFormField>(amount('employment_insurance')).enabled, isFalse);
    final formula = find.descendant(of: card('employment_insurance'),
        matching: find.text('計算式・設定'));
    await t.ensureVisible(formula);
    await t.tap(formula);
    await t.pumpAndSettle();
    expect(find.textContaining('雇用保険の対象支給額 ×'), findsOneWidget);
    await t.tap(find.text('会社の料率'));
    await t.pumpAndSettle();
    expect(opened, 1);
    expect(b.writes, 0);
    expect(t.takeException(), isNull);
  });

  testWidgets('missing calculation stays empty and failed save keeps manual input', (t) async {
    final b = _Backend();
    await _mount(t, b, reader: (_, _, _) async => null);
    expect(t.widget<TextFormField>(amount('health_insurance')).controller!.text, isEmpty);
    expect(find.text('給与計算待ち'), findsNWidgets(5));
    await t.ensureVisible(amount('income_tax'));
    await t.enterText(amount('income_tax'), '1234');
    b.failSave = true;
    await save(t);
    expect(t.widget<TextFormField>(amount('income_tax')).controller!.text, '1234');
    expect(find.textContaining('保存結果を確認できません'), findsOneWidget);
    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, '税・保険料を登録')).onPressed, isNull);
    expect(t.takeException(), isNull);
  });
}

