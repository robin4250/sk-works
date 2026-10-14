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
  Map<String, dynamic> get response => {
    'company_id': 'company', 'worker_id': 'worker', 'can_edit': edit,
    'items': [{'starts_on': month, 'version': version, 'value': value}],
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

Future<void> mount(WidgetTester t, _Backend b, {
  PayrollDeductionStatementReader? reader,
  Future<void> Function()? rates,
}) async {
  await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
    child: PayrollFixedDeductions(
      companyId: 'company', workerId: 'worker', month: month,
      canEdit: b.edit, readStatement: reader ?? b.statement,
      rpc: b.rpc, openRates: rates,
      legacySocialAmount: 12345,
      residentTax: const Text('登録済みの住民税'),
    ),
  )))));
  await t.pumpAndSettle();
}

Future<void> save(WidgetTester t) async {
  final button = find.widgetWithText(FilledButton, '税・保険料を登録');
  await t.ensureVisible(button);
  await t.tap(button);
  await t.pumpAndSettle();
  await t.tap(find.text('確認して保存'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('fixed order, generated amounts, explicit zero and restore automatic', (t) async {
    final b = _Backend();
    await mount(t, b);
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
    await mount(t, b, rates: () async { opened++; });
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
    await mount(t, b, reader: (_, _, _) async => null);
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
