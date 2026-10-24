import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/payroll_tax_conditions_page.dart';

void main() {
  final folder = Platform.environment['SKO_INSURANCE_E2E_DIR'];
  testWidgets('export the actual one-input form save request for isolated PG17', (t) async {
    final state = jsonDecode(await File('$folder/read-state.json').readAsString()) as Map<String, dynamic>;
    Map<String, dynamic>? captured;
    await t.pumpWidget(MaterialApp(home: PayrollTaxConditionsPage(
      companyId: state['company_id'] as String, workerId: state['worker_id'] as String,
      month: DateTime(2026, 10), rpc: (name, params) async {
        if (name == 'read_worker_payroll_tax_conditions') return state;
        expect(name, 'save_worker_payroll_tax_conditions');
        captured = Map<String, dynamic>.from(params);
        return {...state, 'items': [{'starts_on': params['p_starts_on'], 'version': 1, 'value': params['p_value']}]};
      },
    )));
    await t.pumpAndSettle();
    final income = find.byKey(const ValueKey('insurance-reference-average'));
    await t.ensureVisible(income); await t.pumpAndSettle();
    await t.enterText(income, '700000');
    t.testTextInput.hide(); await t.pumpAndSettle();
    final details = find.byKey(const ValueKey('insurance-income-details'));
    await t.ensureVisible(details); await t.pumpAndSettle();
    await t.tap(details); await t.pumpAndSettle();
    final tax = find.byKey(const ValueKey('income-koh'));
    await t.ensureVisible(tax); await t.pumpAndSettle();
    await t.tap(tax); await t.pumpAndSettle();
    await t.tap(find.text('個別設定の固定月額').last); await t.pumpAndSettle();
    final confirmation = find.widgetWithText(CheckboxListTile,
      '扶養人数・保険の加入／未加入・標準報酬月額を確認しました');
    await t.ensureVisible(confirmation); await t.pumpAndSettle();
    await t.tap(confirmation); await t.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, '確認して保存');
    await t.ensureVisible(save); await t.pumpAndSettle();
    await t.tap(save); await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(captured, isNull);
    await t.tap(find.widgetWithText(FilledButton, '確認して保存').last); await t.pumpAndSettle();
    expect(captured, isNotNull);
    final value = captured!['p_value'] as Map;
    expect(value['health_base_yen'], 710000);
    expect(value['pension_base_yen'], 650000);
    expect(value['health'], true); expect(value['pension'], true);
    expect(value['income_mode'], 'fixed');
    await File('$folder/ui-save-request.json').writeAsString(const JsonEncoder.withIndent('  ').convert(captured));
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink()); await t.pump();
  }, skip: folder == null);
}
