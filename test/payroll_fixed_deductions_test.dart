import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/payroll_fixed_deductions.dart';
import 'package:sk_works/features/payroll/resident_tax_section.dart';
import 'features/payroll/resident_tax_section_test.dart' as resident;

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
  bool manualSupported = false;
  bool reasonSupported = true, corruptReceipt = false;
  final reasons = <String>[];
  Map<String, dynamic> get response => {
    'company_id': 'company', 'worker_id': 'worker', 'can_edit': edit,
    if (manualSupported) 'manual_insurance_contract_version': 1,
    'items': hasConditions
        ? [{'starts_on': month, 'version': version, 'value': value}] : [],
  };
  Future<dynamic> rpc(String name, Map<String, dynamic> params) async {
    if (name == 'payroll_deduction_overrides_contract_version') return 1;
    if (name == 'payroll_tax_adjustment_reason_contract_version') return reasonSupported ? 1 : 0;
    if (name == 'read_worker_payroll_tax_conditions') return response;
    expect(name, 'save_worker_payroll_tax_conditions_with_reason');
    expect(params['p_company_id'], 'company');
    expect(params['p_worker_id'], 'worker');
    expect(params['p_starts_on'], month);
    expect(params['p_expected_version'], version);
    expect(params['p_confirmed'], isTrue);
    expect(params['p_reason'], isA<String>());
    expect((params['p_reason'] as String).trim(), isNotEmpty);
    if (failSave) throw StateError('offline');
    sent = Map<String, dynamic>.from(params['p_value'] as Map);
    value = sent!;
    writes++;
    reasons.add(params['p_reason'] as String);
    version++;
    return {...response, 'adjustment_receipt': {
      'starts_on': month, 'version': version,
      'reason': corruptReceipt ? 'different reason' : params['p_reason'],
      'actor_id': '11111111-1111-4111-8111-111111111111',
      'changed_at': '2026-10-30T00:00:00Z',
    }};
  }
  Future<Map<String, dynamic>?> statement(String company, String worker, String period) async {
    expect([company, worker, period], ['company', 'worker', month]);
    final overrides = value['deduction_overrides'] as Map? ?? {};
    final manual = value['manual_insurance_premiums'] as Map?;
    return {'calculation_blocked': false, 'detail': {'tax_calculation': {
      'condition_version': version, 'conditions_start': month,
      'income_tax_yen': overrides['income_tax'] ?? 1000,
      'automatic_income_tax_yen': 1000,
      'automatic_premiums': {
        '雇用保険料': 100, '健康保険料': 5000, '厚生年金保険': 9000, '介護保険料': 0,
      },
      'premiums': {
        '雇用保険料': manual?['employment_insurance'] ?? overrides['employment_insurance'] ?? 100,
        '健康保険料': manual?['health_insurance'] ?? overrides['health_insurance'] ?? 5000,
        '厚生年金保険': manual?['pension_insurance'] ?? overrides['pension_insurance'] ?? 9000,
        '介護保険料': manual?['nursing_insurance'] ?? overrides['nursing_insurance'] ?? 0,
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
  String? selectedMonth = month,
  Widget Function(String, ValueChanged<bool>)? residentBuilder,
  Future<void> Function()? rates,
  Future<void> Function(String month)? conditions,
}) async {
  await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
    child: PayrollFixedDeductions(
      companyId: 'company', workerId: 'worker', month: selectedMonth,
      residentTaxBuilder: residentBuilder,
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
  await t.enterText(find.byKey(const ValueKey('fixed-deduction-adjustment-reason')), '確認した金額に調整');
  await t.pumpAndSettle();
  FocusManager.instance.primaryFocus?.unfocus();
  await t.pumpAndSettle();
  await t.tap(find.text('確認して保存'));
  await t.pumpAndSettle();
}

Future<void> startAdjustment(WidgetTester t, String key) async {
  final button = find.byKey(ValueKey('fixed-deduction-$key-begin-adjustment'));
  await t.ensureVisible(button);
  await t.tap(button);
  await t.pumpAndSettle();
  await t.ensureVisible(amount(key));
}

void main() {
  testWidgets('missing reason capability keeps amounts and general settings readable without manual writes', (t) async {
    final b = _Backend()..reasonSupported = false;
    var conditionsOpened = 0;
    await _mount(t, b, conditions: (_) async => conditionsOpened++);
    expect(t.widget<TextFormField>(amount('health_insurance')).controller!.text, '5000');
    final adjust = find.byKey(const ValueKey('fixed-deduction-health_insurance-begin-adjustment'));
    expect(t.widget<TextButton>(adjust).onPressed, isNull);
    expect(find.text('手動調整を利用できません。管理者に確認してください。'), findsOneWidget);
    final settings = find.widgetWithText(TextButton, '保険料の基準・適用月');
    await t.ensureVisible(settings);
    await t.tap(settings);
    await t.pumpAndSettle();
    expect(conditionsOpened, 1);
    expect(b.writes, 0);
  });

  testWidgets('an adjustment requires a reason and cancellation preserves the entered amount without writes', (t) async {
    final b = _Backend();
    await _mount(t, b);
    await startAdjustment(t, 'health_insurance');
    await t.enterText(amount('health_insurance'), '5100');
    FocusManager.instance.primaryFocus?.unfocus();
    await t.pumpAndSettle();
    final saveButton = find.widgetWithText(FilledButton, '税・保険料を登録');
    await t.ensureVisible(saveButton);
    await t.tap(saveButton);
    await t.pumpAndSettle();
    final confirm = find.widgetWithText(FilledButton, '確認して保存');
    expect(t.widget<FilledButton>(confirm).onPressed, isNull);
    final reason = find.byKey(const ValueKey('fixed-deduction-adjustment-reason'));
    await t.enterText(reason, '   ');
    await t.pumpAndSettle();
    expect(t.widget<FilledButton>(confirm).onPressed, isNull);
    await t.enterText(reason, '  通知額を確認したため  ');
    FocusManager.instance.primaryFocus?.unfocus();
    await t.pumpAndSettle();
    await t.tap(find.text('戻る'));
    await t.pumpAndSettle();
    expect(b.writes, 0);
    expect(t.widget<TextFormField>(amount('health_insurance')).controller!.text, '5100');
    await t.ensureVisible(saveButton);
    await t.tap(saveButton);
    await t.pumpAndSettle();
    expect(t.widget<TextField>(reason).controller!.text, '  通知額を確認したため  ');
    await t.tap(confirm);
    await t.pumpAndSettle();
    expect(b.reasons, ['通知額を確認したため']);
    expect(b.writes, 1);
    expect(t.widget<TextFormField>(amount('health_insurance')).enabled, isFalse);
  });

  testWidgets('a mismatched reason receipt keeps the outcome uncertain and retains the reason for review', (t) async {
    final b = _Backend()..corruptReceipt = true;
    await _mount(t, b);
    await startAdjustment(t, 'income_tax');
    await t.enterText(amount('income_tax'), '1200');
    await save(t);
    expect(find.textContaining('保存結果を確認できません'), findsOneWidget);
    expect(b.writes, 1);
    final reload = find.widgetWithText(TextButton, '税・保険料を再読み込み');
    await t.ensureVisible(reload);
    await t.tap(reload);
    await t.pumpAndSettle();
    await startAdjustment(t, 'income_tax');
    await t.enterText(amount('income_tax'), '1250');
    FocusManager.instance.primaryFocus?.unfocus();
    await t.pumpAndSettle();
    final saveButton = find.widgetWithText(FilledButton, '税・保険料を登録');
    await t.ensureVisible(saveButton);
    await t.tap(saveButton);
    await t.pumpAndSettle();
    expect(t.widget<TextField>(find.byKey(const ValueKey('fixed-deduction-adjustment-reason'))).controller!.text,
      '確認した金額に調整');
    expect(b.writes, 1);
  });

  testWidgets('automatic amounts require a deliberate per-item adjustment and cancel never writes', (t) async {
    final b = _Backend();
    await _mount(t, b);
    for (final item in fixedPayrollDeductions) {
      expect(t.widget<TextFormField>(amount(item.$1)).enabled, isFalse);
    }
    expect(find.text('自動計算専用'), findsOneWidget);
    expect(find.byKey(const ValueKey('fixed-deduction-child_support-begin-adjustment')), findsNothing);
    await startAdjustment(t, 'health_insurance');
    expect(t.widget<TextFormField>(amount('health_insurance')).enabled, isTrue);
    expect(t.widget<TextFormField>(amount('employment_insurance')).enabled, isFalse);
    await t.enterText(amount('health_insurance'), '5100');
    await t.pumpAndSettle();
    expect(helper(t, 'health_insurance'), '手入力修正');
    expect(find.text('手動調整中'), findsOneWidget);
    final cancel = find.byKey(const ValueKey('fixed-deduction-health_insurance-cancel-adjustment'));
    await t.ensureVisible(cancel);
    await t.tap(cancel);
    await t.pumpAndSettle();
    expect(t.widget<TextFormField>(amount('health_insurance')).controller!.text, '5000');
    expect(t.widget<TextFormField>(amount('health_insurance')).enabled, isFalse);
    expect(find.text('手動調整中'), findsNothing);
    expect(b.writes, 0);
    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, '税・保険料を登録')).onPressed, isNull);
  });

  testWidgets('cancelling one open adjustment preserves another draft and saved override cancellation', (t) async {
    final b = _Backend()..value = {...initialProfile, 'deduction_overrides': {'health_insurance': 5200}};
    await _mount(t, b);
    await startAdjustment(t, 'health_insurance');
    await t.enterText(amount('health_insurance'), '5300');
    await startAdjustment(t, 'income_tax');
    await t.enterText(amount('income_tax'), '1100');
    final cancel = find.byKey(const ValueKey('fixed-deduction-health_insurance-cancel-adjustment'));
    await t.ensureVisible(cancel);
    await t.tap(cancel);
    await t.pumpAndSettle();
    expect(t.widget<TextFormField>(amount('health_insurance')).controller!.text, '5200');
    expect(helper(t, 'health_insurance'), '手入力修正');
    expect(t.widget<TextFormField>(amount('income_tax')).controller!.text, '1100');
    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, '税・保険料を登録')).onPressed, isNotNull);
    expect(b.writes, 0);
  });

  for (final calculatorVersion in const [
    'payroll-tax-20261010-v1', 'payroll-tax-20261014-overrides-v1',
  ]) {
    for (final conditionsPresent in [false, true]) {
      testWidgets('saved calculated insurance remains visible when current conditions are ${conditionsPresent ? 'newer' : 'unavailable'} ($calculatorVersion)', (t) async {
        final b = _Backend()..hasConditions = conditionsPresent;
        if (conditionsPresent) {
          b.version = 2;
          b.value = {...initialProfile, 'deduction_overrides': {'health_insurance': 1234}};
        }
        Map<String, dynamic>? saved;
        String? before;
        await _mount(t, b, reader: (company, worker, period) async {
          final row = (await b.statement(company, worker, period))!;
          final tax = (row['detail'] as Map)['tax_calculation'] as Map;
          tax['condition_version'] = 1;
          tax['calculator_version'] = calculatorVersion;
          tax['conditions'] = {'insurance_mode': 'rates'};
          (tax['premiums'] as Map)['健康保険料'] = 5000;
          saved = row;
          before = jsonEncode(row);
          return row;
        });
        expect(t.widget<TextFormField>(amount('health_insurance')).controller!.text, '5000');
        expect(t.widget<TextFormField>(amount('pension_insurance')).controller!.text, '9000');
        expect(t.widget<TextFormField>(amount('health_insurance')).enabled, isFalse);
        expect(helper(t, 'health_insurance'), '保存済みの計算結果（現在の設定とは未照合）');
        expect(find.byKey(const ValueKey('deduction-conditions-missing')), findsNothing);
        expect(jsonEncode(saved), before);
        expect(b.writes, 0);
      });
    }
  }

  Map<String, dynamic> manualProfile() => {
    'insurance_mode': 'manual', 'income_mode': 'koh',
    'dependents': 2, 'non_taxable_yen': 100, 'additional_social_deduction_yen': 0,
    'deduction_overrides': {'income_tax': 800},
    'manual_insurance_premiums': {'health_insurance': 5000, 'pension_insurance': 9000,
      'employment_insurance': 100, 'nursing_insurance': 0, 'child_support': 200},
  };
  for (final premium in <int?>[200, 0, null]) {
    testWidgets('child support uses the statement amount without enabling unsupported overrides ($premium)', (t) async {
      final b = _Backend();
      await _mount(t, b, reader: (company, worker, period) async {
        final row = (await b.statement(company, worker, period))!;
        final tax = (row['detail'] as Map)['tax_calculation'] as Map;
        if (premium != null) {
          (tax['premiums'] as Map)['子ども・子育て支援金'] = premium;
          (tax['automatic_premiums'] as Map)['子ども・子育て支援金'] = premium;
        }
        return row;
      });
      final field = t.widget<TextFormField>(amount('child_support'));
      expect(field.controller!.text, premium?.toString() ?? '');
      expect(field.enabled, isFalse);
      expect(b.writes, 0);
      expect(t.widget<TextFormField>(amount('health_insurance')).controller!.text, '5000');
      expect(t.widget<TextFormField>(amount('pension_insurance')).controller!.text, '9000');
    });
  }

  testWidgets('manual child support stays visible but is changed through existing conditions only', (t) async {
    final b = _Backend()..manualSupported = true..value = manualProfile();
    await _mount(t, b);
    expect(t.widget<TextFormField>(amount('child_support')).controller!.text, '200');
    expect(t.widget<TextFormField>(amount('child_support')).enabled, isFalse);
    expect(helper(t, 'child_support'), '個別手入力（月額）');
    expect(b.writes, 0);
  });

  testWidgets('blocked child support never displays a stale premium', (t) async {
    final b = _Backend();
    await _mount(t, b, reader: (company, worker, period) async {
      final row = (await b.statement(company, worker, period))!;
      row['calculation_blocked'] = true;
      final tax = (row['detail'] as Map)['tax_calculation'] as Map;
      (tax['premiums'] as Map)['子ども・子育て支援金'] = 200;
      return row;
    });
    expect(t.widget<TextFormField>(amount('child_support')).controller!.text, isEmpty);
    expect(helper(t, 'child_support'), '計算結果未確認');
    expect(b.writes, 0);
  });

  testWidgets('manual premium edit preserves other premiums, income override and profile', (t) async {
    final b = _Backend()..manualSupported = true..value = manualProfile();
    await _mount(t, b);
    final field = amount('health_insurance');
    await t.ensureVisible(field); await t.enterText(field, '5100');
    await save(t);
    final expected = manualProfile();
    expected['manual_insurance_premiums'] = {...expected['manual_insurance_premiums'] as Map, 'health_insurance': 5100};
    expect(b.sent, expected);
    expect(b.writes, 1);
  });
  testWidgets('manual profile remains read only without backend capability', (t) async {
    final b = _Backend()..value = manualProfile();
    await _mount(t, b);
    final field = t.widget<TextField>(find.descendant(of: amount('health_insurance'), matching: find.byType(TextField)));
    expect(field.enabled, isFalse);
    expect(b.writes, 0);
  });

  testWidgets('legacy named insurance in saved custom rows stays linked without automatic conditions', (t) async {
    final b = _Backend()..hasConditions = false;
    final snapshot = <String, dynamic>{
      'calculation_blocked': false,
      'detail': {
        '所得税': 6300, '住民税': 12500, '社会保険': 0,
        'custom_deductions': [
          {'name': '健康保険料', 'amount_yen': 5100},
          {'name': '雇用保険料', 'amount_yen': 1200},
          {'name': '厚生年金保険', 'amount_yen': 9000},
          {'name': '介護保険料', 'amount_yen': 0},
        ],
        'unit_resolution': {'contract_version': 1, 'items': [
          {'id': 'common-fixed', 'origin': 'company_common', 'section': 'earning',
            'unit': 'month', 'name': '会社共通手当', 'amount_yen': 700},
        ]},
      },
    };
    final originalSnapshot = jsonDecode(jsonEncode(snapshot));
    await _mount(t, b, reader: (_, _, _) async => snapshot);
    for (final expected in {'income_tax': '6300', 'health_insurance': '5100',
      'employment_insurance': '1200', 'pension_insurance': '9000', 'nursing_insurance': '0'}.entries) {
      expect(t.widget<TextFormField>(amount(expected.key)).controller!.text, expected.value);
      expect(t.widget<TextFormField>(amount(expected.key)).enabled, isFalse);
      expect(helper(t, expected.key), '保存済み明細（自動計算条件未設定）');
    }
    expect(snapshot, originalSnapshot);
    expect((snapshot['detail'] as Map)['住民税'], 12500);
    expect(((snapshot['detail'] as Map)['unit_resolution'] as Map)['items'], [
      {'id': 'common-fixed', 'origin': 'company_common', 'section': 'earning',
        'unit': 'month', 'name': '会社共通手当', 'amount_yen': 700},
    ]);
    expect(b.writes, 0);
  });

  testWidgets('saved scalar zero wins and custom fallback never invents or accepts invalid premiums', (t) async {
    final b = _Backend()..hasConditions = false;
    await _mount(t, b, reader: (_, _, _) async => {
      'calculation_blocked': false,
      'detail': {'健康保険料': 0, '社会保険': 24000,
        'custom_deductions': [
          {'name': '健康保険料', 'amount_yen': 5100},
          {'name': '雇用保険料', 'amount_yen': -1},
          {'name': '厚生年金保険', 'amount_yen': 2000},
          {'name': ' 厚生年金保険 ', 'amount_yen': 3000},
          {'name': '介護保険料', 'amount_yen': '700'},
        ]},
    });
    expect(t.widget<TextFormField>(amount('health_insurance')).controller!.text, '0');
    expect(t.widget<TextFormField>(amount('employment_insurance')).controller!.text, isEmpty);
    expect(t.widget<TextFormField>(amount('pension_insurance')).controller!.text, '5000');
    expect(t.widget<TextFormField>(amount('nursing_insurance')).controller!.text, isEmpty);
    expect(b.writes, 0);
  });

  for (final saved in [1500, 0]) {
    testWidgets('legacy saved income tax stays visible without invented insurance ($saved)', (t) async {
      final b = _Backend()..hasConditions = false;
      var failRead = false;
      final snapshot = <String, dynamic>{
        'calculation_blocked': false,
        'detail': {'所得税': saved, '社会保険': 24000},
      };
      await _mount(t, b, reader: (company, worker, period) async {
        expect([company, worker, period], ['company', 'worker', month]);
        if (failRead) throw StateError('offline');
        return snapshot;
      });
      expect(t.widget<TextFormField>(amount('income_tax')).controller!.text, '$saved');
      expect(helper(t, 'income_tax'), '保存済み明細（自動計算条件未設定）');
      expect(t.widget<TextFormField>(amount('income_tax')).enabled, isFalse);
      for (final item in fixedPayrollDeductions.skip(1)) {
        expect(t.widget<TextFormField>(amount(item.$1)).controller!.text, isEmpty);
      }
      expect((snapshot['detail'] as Map).containsKey('tax_calculation'), isFalse);
      failRead = true;
      final reload = find.widgetWithText(TextButton, '税・保険料を再読み込み');
      await t.ensureVisible(reload);
      await t.pumpAndSettle();
      await t.tap(reload);
      await t.pumpAndSettle();
      expect(t.widget<TextFormField>(amount('income_tax')).controller!.text, isEmpty);
      expect(helper(t, 'income_tax'), '計算結果未確認');
      expect(b.writes, 0);
    });
  }

  testWidgets('saved named insurance stays visible and read-only without conditions', (t) async {
    final b = _Backend()..hasConditions = false;
    final detail = <String, dynamic>{
      '所得税': 1500, '雇用保険料': 123, '健康保険料': 5000,
      '厚生年金保険': 9000, '介護保険料': 0, '子ども・子育て支援金': 200, '社会保険': 24000,
    };
    await _mount(t, b, reader: (_, _, _) async =>
        {'calculation_blocked': false, 'detail': detail});
    for (final item in fixedPayrollDeductions) {
      final field = t.widget<TextFormField>(amount(item.$1));
      expect(field.controller!.text, '${detail[item.$3]}');
      expect(field.enabled, isFalse);
      expect(helper(t, item.$1), '保存済み明細（自動計算条件未設定）');
    }
    expect(find.text('自動計算に戻す'), findsNothing);
    expect(b.writes, 0);
    expect(detail['社会保険'], 24000);
    expect(detail.containsKey('tax_calculation'), isFalse);
  });

  testWidgets('blocked and malformed named insurance are never substituted from aggregate', (t) async {
    for (final bad in [null, -1, '123', 1.5, 2147483648]) {
      final b = _Backend()..hasConditions = false;
      await _mount(t, b, reader: (_, _, _) async => {
        'calculation_blocked': false,
        'detail': {'雇用保険料': bad, '健康保険料': bad,
          '厚生年金保険': bad, '介護保険料': bad, '社会保険': 24000},
      });
      for (final item in fixedPayrollDeductions.skip(1)) {
        expect(t.widget<TextFormField>(amount(item.$1)).controller!.text, isEmpty);
      }
      await t.pumpWidget(const SizedBox.shrink());
    }
    final b = _Backend()..hasConditions = false;
    await _mount(t, b, reader: (_, _, _) async => {
      'calculation_blocked': true,
      'detail': {'雇用保険料': 123, '健康保険料': 5000,
        '厚生年金保険': 9000, '介護保険料': 0},
    });
    for (final item in fixedPayrollDeductions.skip(1)) {
      expect(t.widget<TextFormField>(amount(item.$1)).controller!.text, isEmpty);
    }
    expect(b.writes, 0);
  });

  testWidgets('future conditions do not hide an earlier saved legacy tax', (t) async {
    final b = _Backend();
    await _mount(t, b, selectedMonth: '2026-09-01', reader: (_, _, period) async {
      expect(period, '2026-09-01');
      return {'calculation_blocked': false, 'detail': {'所得税': 1800}};
    });
    expect(t.widget<TextFormField>(amount('income_tax')).controller!.text, '1800');
    expect(helper(t, 'income_tax'), '保存済み明細（自動計算条件未設定）');
    expect(b.writes, 0);
  });

  testWidgets('blocked or malformed legacy tax never becomes a displayed amount', (t) async {
    final b = _Backend()..hasConditions = false;
    for (final snapshot in <Map<String, dynamic>>[
      {'calculation_blocked': true, 'detail': {'所得税': 1500}},
      {'calculation_blocked': false, 'detail': {'所得税': -1}},
      {'calculation_blocked': false, 'detail': {'所得税': '1500'}},
    ]) {
      await t.pumpWidget(const SizedBox.shrink());
      await _mount(t, b, reader: (_, _, _) async => snapshot);
      expect(t.widget<TextFormField>(amount('income_tax')).controller!.text, isEmpty);
      expect(b.writes, 0);
    }
  });

  for (final lostReply in [false, true]) {
  testWidgets('month navigation protects resident edits and uncertain save ($lostReply)', (t) async {
    final b = _Backend()..hasConditions = false;
    final residentRepository = resident.FakeResidentTaxRepository()..loseReply = lostReply;
    final readMonths = <String>[];
    await _mount(t, b, selectedMonth: null,
      reader: (_, _, period) async { readMonths.add(period); return null; },
      residentBuilder: (period, onEditingChanged) => ResidentTaxSection(
        workerId: 'worker', companyId: 'company', month: period,
        canEdit: true, legacyAmount: 4000, repository: residentRepository,
        onEditingChanged: onEditingChanged,
      ));
    final initial = DateTime.parse(readMonths.single);
    final next = DateTime(initial.year, initial.month + 1);
    final nextMonth = '${next.year.toString().padLeft(4, '0')}-'
        '${next.month.toString().padLeft(2, '0')}-01';
    final arrow = find.byKey(const ValueKey('deductions-next-month'));
    await t.ensureVisible(arrow);
    await t.pumpAndSettle();
    await t.tap(arrow);
    await t.pumpAndSettle();
    expect(readMonths.last, nextMonth);
    expect(find.text('${nextMonth.substring(0, 7)}の住民税：4000円'), findsOneWidget);
    final residentAmount = find.byKey(const ValueKey('resident-amount'));
    await t.ensureVisible(residentAmount);
    await t.enterText(residentAmount, '5000');
    await t.pumpAndSettle();
    expect(t.widget<IconButton>(arrow).onPressed, isNull);
    expect(readMonths.length, 2);
    final saveResident = find.text('住民税だけ保存');
    FocusManager.instance.primaryFocus?.unfocus();
    await t.ensureVisible(saveResident);
    await t.pumpAndSettle();
    await t.tap(saveResident);
    await t.pumpAndSettle();
    expect(t.widget<IconButton>(arrow).onPressed, isNull);
    await t.tap(find.text('確認して保存'));
    await t.pumpAndSettle();
    expect(residentRepository.saves, 1);
    if (lostReply) {
      expect(t.widget<IconButton>(arrow).onPressed, isNull);
      final reload = find.text('住民税を再読み込み');
      await t.ensureVisible(reload);
      await t.pumpAndSettle();
      await t.tap(reload);
      await t.pumpAndSettle();
      expect(find.text('住民税の保存を確認しました'), findsOneWidget);
    }
    expect(t.widget<IconButton>(arrow).onPressed, isNotNull);
    final previous = find.byKey(const ValueKey('deductions-previous-month'));
    await t.ensureVisible(previous);
    await t.pumpAndSettle();
    await t.tap(previous);
    await t.pumpAndSettle();
    expect(readMonths.last, readMonths.first);
    expect(find.text('${readMonths.first.substring(0, 7)}の住民税：4000円'), findsOneWidget);
    expect(residentRepository.saves, 1);
    expect(b.writes, 0);
    expect(t.takeException(), isNull);
  });

  }

  testWidgets('disposed deduction panel stops before fetching conditions', (t) async {
    final contract = Completer<dynamic>();
    final calls = <String>[];
    await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: PayrollFixedDeductions(
      companyId: 'company', workerId: 'worker', month: month,
      residentTax: const SizedBox.shrink(),
      readStatement: (_, _, _) async => throw StateError('must not read'),
      rpc: (name, params) {
        calls.add(name);
        return contract.future;
      },
    )))));
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
    final setup = find.widgetWithText(TextButton, '保険料の基準・適用月');
    await t.ensureVisible(setup);
    await t.pumpAndSettle();
    await t.tap(setup);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('deduction-conditions-missing')), findsNothing);
    expect(setup, findsOneWidget); // Existing conditions remain directly editable.
    expect(helper(t, 'income_tax'), '自動計算');
    expect(t.widget<TextFormField>(amount('income_tax')).controller!.text, '1000');
    expect(b.writes, 0);
  });

  testWidgets('condition setup receives the same month as the deduction statement', (t) async {
    final b = _Backend()..hasConditions = false;
    String? inspected;
    await _mount(t, b, conditions: (month) async { inspected = month; });
    final setup = find.widgetWithText(TextButton, '保険料の基準・適用月');
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
    await startAdjustment(t, 'health_insurance');
    await t.enterText(amount('health_insurance'), '5100');
    await t.ensureVisible(amount('employment_insurance'));
    await startAdjustment(t, 'employment_insurance');
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
    expect(b.reasons, ['確認した金額に調整', '確認した金額に調整']);
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
    for (final item in fixedPayrollDeductions) {
      expect(helper(t, item.$1), '給与計算待ち');
    }
    await t.ensureVisible(amount('income_tax'));
    await startAdjustment(t, 'income_tax');
    await t.enterText(amount('income_tax'), '1234');
    b.failSave = true;
    await save(t);
    expect(t.widget<TextFormField>(amount('income_tax')).controller!.text, '1234');
    expect(find.textContaining('保存結果を確認できません'), findsOneWidget);
    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, '税・保険料を登録')).onPressed, isNull);
    expect(t.takeException(), isNull);
  });
  testWidgets('missing conditions explains blank amounts and keeps saved tax and resident values', (t) async {
    final b = _Backend()..hasConditions = false;
    var opened = 0;
    await _mount(t, b, conditions: (selected) async {
      expect(selected, month);
      opened++;
    }, residentBuilder: (_, __) => const Text('住民税2500円'),
    reader: (_, _, _) async => {
      'calculation_blocked': false,
      'detail': {'所得税': 1500, '住民税': 2500},
    });
    expect(find.byKey(const ValueKey('deduction-conditions-missing')), findsOneWidget);
    expect(find.textContaining('空欄は保険料0円を意味しません'), findsOneWidget);
    expect(t.widget<TextFormField>(amount('income_tax')).controller!.text, '1500');
    expect(t.widget<TextFormField>(amount('health_insurance')).controller!.text, isEmpty);
    expect(find.text('住民税2500円'), findsOneWidget);
    final link = find.widgetWithText(TextButton, '保険料の基準・適用月');
    await t.ensureVisible(link);
    await t.tap(link);
    await t.pumpAndSettle();
    expect(opened, 1);
    expect(t.widget<TextFormField>(amount('income_tax')).controller!.text, '1500');
    expect(b.writes, 0);
  });

  testWidgets('failed read does not claim conditions are missing', (t) async {
    final b = _Backend()..hasConditions = false;
    await _mount(t, b, conditions: (_) async {}, reader: (_, _, _) async {
      throw StateError('offline');
    });
    expect(find.byKey(const ValueKey('deduction-conditions-missing')), findsNothing);
    expect(find.textContaining('計算結果を取得できません'), findsOneWidget);
    expect(find.text('保険料の基準・適用月'), findsNothing);
    expect(b.writes, 0);
  });

  for (final uncertain in [false, true]) {
    testWidgets('conditions navigation preserves ${uncertain ? 'uncertain' : 'dirty'} correction', (t) async {
      final b = _Backend();
      var opened = 0;
      await _mount(t, b, conditions: (_) async { opened++; });
      await t.ensureVisible(amount('income_tax'));
      await startAdjustment(t, 'income_tax');
    await t.enterText(amount('income_tax'), '1234');
      if (uncertain) {
        b.failSave = true;
        await save(t);
      }
      final formula = find.descendant(of: card('income_tax'),
          matching: find.text('計算式・設定'));
      await t.ensureVisible(formula);
      await t.tap(formula);
      await t.pumpAndSettle();
      await t.tap(find.text('個別の計算条件'));
      await t.pumpAndSettle();
      expect(opened, 0);
      expect(t.widget<TextFormField>(amount('income_tax')).controller!.text, '1234');
      expect(b.writes, 0);
      expect(t.takeException(), isNull);
    });
  }

}
