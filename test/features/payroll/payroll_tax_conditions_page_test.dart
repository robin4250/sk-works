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

  testWidgets('initial setup selects automatic modes without writing payroll', (
    t,
  ) async {
    final calls = <String>[];
    await open(t, (name, params) async {
      calls.add(name);
      return state();
    });
    expect(find.text('はじめての自動計算設定'), findsOneWidget);
    final modes = t
        .widgetList<DropdownButtonFormField<String>>(
          find.byType(DropdownButtonFormField<String>),
        )
        .map((field) => field.initialValue);
    expect(modes, ['koh', 'rates']);
    await tapSave(t);
    expect(find.byType(AlertDialog), findsNothing);
    expect(calls, ['read_worker_payroll_tax_conditions']);
  });

  testWidgets('confirmed initial setup saves automatic modes and hides guide', (
    t,
  ) async {
    Map<String, dynamic>? sent;
    await open(t, (name, params) async {
      if (name.startsWith('read_')) return state();
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
    final confirmation = find.widgetWithText(
      CheckboxListTile,
      '扶養人数・保険の加入／未加入・標準報酬月額を確認しました',
    );
    await t.scrollUntilVisible(
      confirmation,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(confirmation);
    await t.pumpAndSettle();
    await tapSave(t);
    expect(sent, isNull);
    await t.tap(find.widgetWithText(FilledButton, '確認して保存').last);
    await t.pumpAndSettle();
    expect(sent!['p_expected_version'], 0);
    expect(sent!['p_value'], {
      ...value,
      'income_mode': 'koh',
      'insurance_mode': 'rates',
    });
    await t.drag(find.byType(ListView), const Offset(0, 4000));
    await t.pumpAndSettle();
    expect(find.text('はじめての自動計算設定'), findsNothing);
  });
  testWidgets('stored fixed settings survive opening the updated app', (
    t,
  ) async {
    await open(
      t,
      (name, params) async => state(
        items: [
          {
            'starts_on': '2026-04-01',
            'version': 3,
            'value': {...value, 'dependents': 2},
          },
        ],
      ),
    );
    expect(find.text('はじめての自動計算設定'), findsNothing);
    final modes = t
        .widgetList<DropdownButtonFormField<String>>(
          find.byType(DropdownButtonFormField<String>),
        )
        .map((field) => field.initialValue);
    expect(modes, ['2026-04-01', 'fixed', 'fixed']);
  });
  testWidgets('switching to an unconfigured worker resets the previous draft', (
    t,
  ) async {
    Future<dynamic> rpc(String name, Map<String, dynamic> params) async => {
      ...state(),
      'worker_id': params['p_worker_id'],
      'items': params['p_worker_id'] == 'worker'
          ? [
              {
                'starts_on': '2026-04-01',
                'version': 1,
                'value': {
                  ...value,
                  'dependents': 3,
                  'health': true,
                  'health_base_yen': 300000,
                },
              },
            ]
          : [],
    };
    await open(t, rpc);
    await t.pumpWidget(
      MaterialApp(
        home: PayrollTaxConditionsPage(
          companyId: 'company',
          workerId: 'other',
          rpc: rpc,
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('はじめての自動計算設定'), findsOneWidget);
    expect(
      t
          .widgetList<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .map((field) => field.initialValue),
      ['koh', 'rates'],
    );
    expect(
      t
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .every((field) => field.value == false),
      isTrue,
    );
    expect(
      t
          .widgetList<TextFormField>(find.byType(TextFormField))
          .any((field) => field.controller?.text == '300000'),
      isFalse,
    );
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
      if (name.startsWith('read_')) {
        return state(
          items: [
            {'starts_on': '2020-01-01', 'version': 1, 'value': value},
          ],
        );
      }
      writes++;
      sent = params;
      return state(
        items: [
          {
            'starts_on': params['p_starts_on'],
            'version': 2,
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
    expect(sent!['p_expected_version'], 1);
    expect(sent!['p_value'], value);
    await t.drag(find.byType(ListView), const Offset(0, 2000));
    await t.pumpAndSettle();
    expect(find.text('保存しました。対象の未確定給与へ反映しました。'), findsOneWidget);
  });
  testWidgets('lost response cannot report success or send another write', (
    t,
  ) async {
    await open(t, (name, params) async {
      if (name.startsWith('read_')) {
        return state(
          items: [
            {'starts_on': '2020-01-01', 'version': 1, 'value': value},
          ],
        );
      }
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
