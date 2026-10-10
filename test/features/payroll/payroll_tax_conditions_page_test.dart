import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/payroll_tax_conditions_page.dart';

void main() {
  final value = <String, dynamic>{
    'insurance_mode': 'fixed',
    'income_mode': 'fixed',
    'health': false,
    'pension': false,
    'employment': false,
    'nursing': false,
    'child_support': false,
    'birth_date': null,
    'health_base_yen': 0,
    'pension_base_yen': 0,
    'dependents': 0,
    'non_taxable_yen': 0,
    'employment_excluded_yen': 0,
    'additional_social_deduction_yen': 0,
  };
  Map<String, dynamic> state({
    bool edit = true,
    List<dynamic> items = const [],
  }) => {
    'company_id': 'company',
    'worker_id': 'worker',
    'can_edit': edit,
    'items': items,
  };
  Future<void> open(WidgetTester t, PayrollTaxRpc rpc) async {
    await t.pumpWidget(
      MaterialApp(
        home: PayrollTaxConditionsPage(
          companyId: 'company',
          workerId: 'worker',
          rpc: rpc,
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> tapSave(WidgetTester t) async {
    final button = find.widgetWithText(FilledButton, '確認して保存');
    await t.scrollUntilVisible(
      button,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await t.ensureVisible(button);
    await t.pumpAndSettle();
    await t.drag(find.byType(ListView), const Offset(0, -100));
    await t.pumpAndSettle();
    await t.tap(button);
    await t.pumpAndSettle();
  }

  testWidgets('unconfigured state does not silently enable automatic taxes', (
    t,
  ) async {
    await open(t, (name, params) async => state());
    expect(find.text('未設定：現在は従来の固定月額を使用しています。'), findsOneWidget);
    expect(find.text('個別設定の固定月額'), findsWidgets);
  });
  testWidgets('reader can inspect but cannot save conditions', (t) async {
    await open(t, (name, params) async => state(edit: false));
    expect(find.byType(FilledButton), findsNothing);
  });
  testWidgets('cancel is write free and confirmation saves effective month', (
    t,
  ) async {
    var writes = 0;
    Map<String, dynamic>? sent;
    await open(t, (name, params) async {
      if (name.startsWith('read_')) return state();
      writes++;
      sent = params;
      return state(
        items: [
          {
            'starts_on': params['p_starts_on'],
            'version': 1,
            'value': params['p_value'],
          },
        ],
      );
    });
    await tapSave(t);
    await t.tap(find.text('戻る'));
    await t.pumpAndSettle();
    expect(writes, 0);
    await tapSave(t);
    await t.tap(find.widgetWithText(FilledButton, '確認して保存').last);
    await t.pumpAndSettle();
    expect(writes, 1);
    expect(sent!['p_expected_version'], 0);
    expect(sent!['p_value'], value);
    await t.drag(find.byType(ListView), const Offset(0, 2000));
    await t.pumpAndSettle();
    expect(find.text('保存しました。対象の未確定給与へ反映しました。'), findsOneWidget);
  });
  testWidgets('lost response cannot report success or send another write', (
    t,
  ) async {
    await open(t, (name, params) async {
      if (name.startsWith('read_')) return state();
      throw TimeoutException('lost reply');
    });
    await tapSave(t);
    await t.tap(find.widgetWithText(FilledButton, '確認して保存').last);
    await t.pumpAndSettle();
    expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    await t.drag(find.byType(ListView), const Offset(0, 2000));
    await t.pumpAndSettle();
    expect(find.textContaining('保存結果を確認できません'), findsOneWidget);
  });
  testWidgets('failed reload hides previously loaded employee conditions', (
    t,
  ) async {
    var fail = false;
    await open(t, (name, params) async {
      if (fail) throw StateError('unavailable');
      return state(
        items: [
          {
            'starts_on': '2026-10-01',
            'version': 1,
            'value': {...value, 'health_base_yen': 123456},
          },
        ],
      );
    });
    fail = true;
    final reload = find.widgetWithText(TextButton, '再読み込み');
    await t.scrollUntilVisible(
      reload,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(reload);
    await t.pumpAndSettle();
    expect(find.byType(Form), findsNothing);
    expect(find.textContaining('税計算条件を取得できません'), findsOneWidget);
    fail = false;
    await t.tap(find.text('再読み込み'));
    await t.pumpAndSettle();
    expect(find.byType(Form), findsOneWidget);
  });
  testWidgets('another company response never enables editing', (t) async {
    await open(t, (name, params) async => {...state(), 'company_id': 'other'});
    expect(find.byType(FilledButton), findsNothing);
    expect(find.textContaining('税計算条件を取得できません'), findsOneWidget);
  });
}
