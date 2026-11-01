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
    'birth_source': 'personal_uid_v1',
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
    for (final key in ['insurance-income-details', 'insurance-enrollment-details']) {
      final tile = find.byKey(ValueKey(key));
      if (tile.evaluate().isNotEmpty) {
        await t.ensureVisible(tile); await t.pumpAndSettle();
        await t.tap(tile); await t.pumpAndSettle();
      }
    }
    if (find.byType(ListView).evaluate().isNotEmpty) {
      await t.drag(find.byType(ListView), const Offset(0, 4000));
      await t.pumpAndSettle();
    }
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

  test('manual amounts require all five explicit integers without invented conditions', () {
    final premiums = {for (final key in manualPayrollInsuranceLabels.keys) key: 0};
    final manual = <String, dynamic>{'insurance_mode': 'manual',
      'income_mode': 'fixed', 'manual_insurance_premiums': premiums,
      'dependents': 0, 'non_taxable_yen': 0, 'additional_social_deduction_yen': 0};
    expect(validManualPayrollInsurance(manual), isTrue);
    for (final invalid in [null, '', -1, 0.5, 2147483648]) {
      expect(validManualPayrollInsurance({...manual,
        'manual_insurance_premiums': {...premiums, 'health_insurance': invalid}}), isFalse);
    }
    expect(validManualPayrollInsurance({...manual, 'health': false}), isFalse);
    expect(validManualPayrollInsurance({...manual, 'deduction_overrides': {'health_insurance': 10}}), isFalse);
  });

  testWidgets('manual entry is unavailable on an unprepared backend', (t) async {
    await open(t, (_, __) async => state());
    final insurance = find.byKey(const ValueKey('insurance-rates'));
    await t.ensureVisible(insurance); await t.pumpAndSettle();
    await t.tap(insurance); await t.pumpAndSettle();
    expect(find.text('保険別の月額を手入力'), findsNothing);
    expect(find.text('会社の登録料率で自動計算'), findsWidgets);
  });

  testWidgets('manual selection is explicit, preserves fixed income and rejects empty amounts', (t) async {
    final calls = <String>[];
    await open(t, (name, params) async {
      calls.add(name);
      return {...state(), 'manual_insurance_contract_version': 1};
    });
    final insurance = find.byKey(const ValueKey('insurance-rates'));
    await t.ensureVisible(insurance); await t.pumpAndSettle();
    await t.tap(insurance); await t.pumpAndSettle();
    await t.tap(find.text('保険別の月額を手入力').last); await t.pumpAndSettle();
    // ListView builds fields lazily; reveal each field before asserting its key.
    await t.scrollUntilVisible(find.byKey(const ValueKey('income-fixed')), -250,
      scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const ValueKey('income-fixed')), findsOneWidget);
    await t.scrollUntilVisible(find.byKey(const ValueKey('manual-insurance-health_insurance')), 250,
      scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const ValueKey('manual-insurance-health_insurance')), findsOneWidget);
    await tapSave(t);
    expect(find.byType(AlertDialog), findsNothing);
    expect(calls, ['read_worker_payroll_tax_conditions']);
  });

  testWidgets('confirmed explicit zero premiums save no synthetic enrollment or base', (t) async {
    Map<String, dynamic>? sent;
    await open(t, (name, params) async {
      if (name.startsWith('read_')) return {...state(), 'manual_insurance_contract_version': 1};
      sent = params;
      return {...state(items: [{'starts_on': params['p_starts_on'], 'version': 1,
        'value': params['p_value']}]), 'manual_insurance_contract_version': 1};
    });
    final insurance = find.byKey(const ValueKey('insurance-rates'));
    await t.ensureVisible(insurance); await t.pumpAndSettle();
    await t.tap(insurance); await t.pumpAndSettle();
    await t.tap(find.text('保険別の月額を手入力').last); await t.pumpAndSettle();
    for (final key in manualPayrollInsuranceLabels.keys) {
      final field = find.byKey(ValueKey('manual-insurance-$key'));
      await t.scrollUntilVisible(field, 250, scrollable: find.byType(Scrollable).first);
      await t.enterText(field, '0'); t.testTextInput.hide(); await t.pumpAndSettle();
    }
    final confirmation = find.widgetWithText(CheckboxListTile, '本人負担の各月額・該当なしの0円・適用月を確認しました');
    await t.scrollUntilVisible(confirmation, 250, scrollable: find.byType(Scrollable).first);
    await t.ensureVisible(confirmation);
    await t.pumpAndSettle();
    await t.tap(confirmation); await t.pumpAndSettle();
    await tapSave(t);
    expect(find.byType(AlertDialog), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, '確認して保存').last); await t.pumpAndSettle();
    expect(sent, isNotNull);
    final saved = sent!['p_value'] as Map;
    expect(saved['insurance_mode'], 'manual'); expect(saved['income_mode'], 'fixed');
    expect(saved['manual_insurance_premiums'], {for (final key in manualPayrollInsuranceLabels.keys) key: 0});
    for (final key in ['health', 'pension', 'employment', 'nursing', 'birth_date', 'health_base_yen', 'pension_base_yen']) {
      expect(saved.containsKey(key), isFalse);
    }
    expect(sent!['p_expected_version'], 0); expect(sent!['p_confirmed'], isTrue);
  });

  testWidgets('target month opens its effective profile before a future profile', (t) async {
    final calls = <String>[];
    await t.pumpWidget(MaterialApp(home: PayrollTaxConditionsPage(
      companyId: 'company', workerId: 'worker', month: DateTime(2026, 10),
      rpc: (name, params) async {
        calls.add(name);
        return state(items: [
          {'starts_on': '2026-12-01', 'version': 2,
            'value': {...value, 'dependents': 4}},
          {'starts_on': '2026-04-01', 'version': 3,
            'value': {...value, 'dependents': 2}},
        ]);
      },
    )));
    await t.pumpAndSettle();
    final selector = t.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>, skipOffstage: false).first);
    expect(selector.initialValue, '2026-04-01');
    expect(find.text('2026-04'), findsWidgets);
    expect(calls, ['read_worker_payroll_tax_conditions']);
  });

  testWidgets('changing inspected month reloads the matching saved profile', (t) async {
    final calls = <String>[];
    Future<dynamic> rpc(String name, Map<String, dynamic> params) async {
      calls.add(name);
      // The result need not be ordered by the transport.
      return state(items: [
        {'starts_on': '2026-04-01', 'version': 3, 'value': value},
        {'starts_on': '2026-12-01', 'version': 2, 'value': value},
      ]);
    }
    Future<void> showMonth(int month) async {
      await t.pumpWidget(MaterialApp(home: PayrollTaxConditionsPage(
        companyId: 'company', workerId: 'worker', month: DateTime(2026, month),
        rpc: rpc,
      )));
      await t.pumpAndSettle();
    }
    await showMonth(10);
    expect(t.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>, skipOffstage: false).first).initialValue, '2026-04-01');
    await showMonth(12);
    expect(t.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>, skipOffstage: false).first).initialValue, '2026-12-01');
    expect(find.text('2026-12'), findsWidgets);
    expect(calls, ['read_worker_payroll_tax_conditions', 'read_worker_payroll_tax_conditions']);
  });

  testWidgets('future-only settings are identified without creating current conditions', (t) async {
    final calls = <String>[];
    await t.pumpWidget(MaterialApp(home: PayrollTaxConditionsPage(
      companyId: 'company', workerId: 'worker', month: DateTime(2026, 10),
      rpc: (name, params) async {
        calls.add(name);
        return state(items: [
          {'starts_on': '2026-12-01', 'version': 2, 'value': value},
        ]);
      },
    )));
    await t.pumpAndSettle();
    expect(find.text('2026-10分に適用される税計算条件は未登録です。表示中の登録済み条件は将来分です。'), findsOneWidget);
    expect(t.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>, skipOffstage: false).first).initialValue, '2026-12-01');
    expect(find.text('はじめての自動計算設定'), findsNothing);
    expect(calls, ['read_worker_payroll_tax_conditions']);
  });

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
          find.byType(DropdownButtonFormField<String>, skipOffstage: false),
        )
        .map((field) => field.initialValue);
    expect(modes, ['koh', 'rates', 'kenpo']);
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
    final income = find.byKey(const ValueKey('insurance-reference-average'));
    await t.ensureVisible(income); await t.pumpAndSettle();
    await t.enterText(income, '300000');
    t.testTextInput.hide(); await t.pumpAndSettle();
    final confirmation = find.widgetWithText(
      CheckboxListTile,
      '扶養人数・保険の加入／未加入・標準報酬月額を確認しました',
    );
    await t.scrollUntilVisible(
      confirmation,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await t.ensureVisible(confirmation);
    await t.pumpAndSettle();
    await t.tap(confirmation);
    await t.pumpAndSettle();
    await tapSave(t);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(sent, isNull);
    await t.tap(find.widgetWithText(FilledButton, '確認して保存').last);
    await t.pumpAndSettle();
    expect(sent!['p_expected_version'], 0);
    expect(sent!['p_value'], {
      ...value,
      'income_mode': 'koh',
      'insurance_mode': 'rates',
      'health': true,
      'pension': true,
      'health_base_yen': 300000,
      'pension_base_yen': 300000,
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
          find.byType(DropdownButtonFormField<String>, skipOffstage: false),
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
    for (final key in ['insurance-income-details', 'insurance-enrollment-details']) {
      final details = find.byKey(ValueKey(key));
      await t.ensureVisible(details); await t.pumpAndSettle();
      await t.tap(details); await t.pumpAndSettle();
    }
    expect(find.text('はじめての自動計算設定'), findsOneWidget);
    expect(
      t
          .widgetList<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>, skipOffstage: false),
          )
          .map((field) => field.initialValue),
      ['koh', 'rates', 'kenpo'],
    );
    await t.scrollUntilVisible(
      find.widgetWithText(CheckboxListTile, '健康保険'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      t
          .widget<CheckboxListTile>(
            find.widgetWithText(CheckboxListTile, '健康保険'),
          )
          .value,
      isTrue,
    );
    expect(
      t
          .widget<CheckboxListTile>(
            find.widgetWithText(CheckboxListTile, '厚生年金'),
          )
          .value,
      isTrue,
    );
    expect(
      t
          .widget<CheckboxListTile>(
            find.widgetWithText(CheckboxListTile, '子ども・子育て支援金'),
          )
          .value,
      isFalse,
    );
    expect(
      t
          .widgetList<TextFormField>(find.byType(TextFormField, skipOffstage: false))
          .any((field) => field.controller?.text == '300000'),
      isFalse,
    );
  });

  testWidgets(
    'national insurance clears only health and pension without saving',
    (t) async {
      var writes = 0;
      await open(t, (name, params) async {
        if (!name.startsWith('read_')) writes++;
        return state();
      });
      final plan = find.byKey(const ValueKey('insurance-plan-kenpo'));
      await t.scrollUntilVisible(
        plan,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await t.ensureVisible(plan);
      await t.pumpAndSettle();
      await t.tap(plan);
      await t.pumpAndSettle();
      await t.tap(find.text('国保・社会保険未加入').last);
      await t.pumpAndSettle();
      expect(
        t
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, '健康保険'),
            )
            .value,
        isFalse,
      );
      expect(
        t
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, '厚生年金'),
            )
            .value,
        isFalse,
      );
      expect(
        t
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, '子ども・子育て支援金'),
            )
            .value,
        isFalse,
      );
      await t.tap(find.byKey(const ValueKey('insurance-plan-kokuho')));
      await t.pumpAndSettle();
      await t.tap(find.text('けんぽ').last);
      await t.pumpAndSettle();
      expect(
        t
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, '健康保険'),
            )
            .value,
        isTrue,
      );
      expect(
        t
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, '厚生年金'),
            )
            .value,
        isTrue,
      );
      expect(writes, 0);
    },
  );
  testWidgets(
    'initial kenpo requires actual standard remuneration before save',
    (t) async {
      var writes = 0;
      await open(t, (name, params) async {
        if (!name.startsWith('read_')) writes++;
        return state();
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
      await t.ensureVisible(confirmation);
      await t.pumpAndSettle();
      await t.ensureVisible(confirmation);
    await t.pumpAndSettle();
    await t.tap(confirmation);
      await t.pumpAndSettle();
      await tapSave(t);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(const ValueKey('insurance-base-input-error')), findsOneWidget);
      expect(find.text('平均月収を入力するか、「通知書の金額で手動修正」から加入している保険の標準報酬月額を入力してください。'), findsOneWidget);
      expect(find.byKey(const ValueKey('insurance-base-input-error')).hitTestable(), findsOneWidget);
      expect(writes, 0);
    },
  );

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
    await t.ensureVisible(reload);
    await t.pumpAndSettle();
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
  for (final invalidDate in ['abc', '2026-02-30']) {
    for (final fixedMode in [false, true]) {
    testWidgets('canonical DOB ignores legacy invalid company birth date: $invalidDate fixed=$fixedMode', (t) async {
      var writes = 0;
      await open(t, (name, params) async {
        if (!name.startsWith('read_')) {
          writes++; expect((params['p_value'] as Map)['birth_date'], null);
        }
        return state(items: [{'starts_on': '2026-10-01', 'version': 1, 'value': {
          ...value, 'insurance_mode': 'rates', 'health': true, 'pension': true,
          'health_base_yen': 300000, 'pension_base_yen': 300000, 'birth_date': invalidDate,
        }}]);
      });
      final nursing = find.widgetWithText(CheckboxListTile, '介護保険（40〜64歳を自動判定）');
      await t.ensureVisible(nursing); await t.pumpAndSettle();
      await t.tap(nursing); await t.pumpAndSettle();
      final birth = find.widgetWithText(TextFormField, '生年月日（YYYY-MM-DD）');
      expect(birth, findsNothing);
      await t.ensureVisible(nursing); await t.pumpAndSettle();
      await t.tap(nursing); await t.pumpAndSettle();
      if (fixedMode) {
        final mode = find.byKey(const ValueKey('insurance-rates'));
        await t.ensureVisible(mode); await t.pumpAndSettle();
        await t.tap(mode); await t.pumpAndSettle();
        await t.tap(find.text('個別設定の固定月額').last); await t.pumpAndSettle();
      }
      expect(birth, findsNothing);
      await tapSave(t); expect(find.byType(AlertDialog), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, '確認して保存').last);
      await t.pumpAndSettle(); expect(writes, 1);
    });
    }
  }

  testWidgets('canonical nursing source saves no company birth date', (t) async {
    var version = 1, writes = 0;
    var saved = <String, dynamic>{...value, 'insurance_mode': 'rates',
      'health': true, 'pension': true, 'health_base_yen': 300000, 'pension_base_yen': 300000};
    await open(t, (name, params) async {
      if (!name.startsWith('read_')) {
        writes++;
        saved = Map<String, dynamic>.from(params['p_value'] as Map);
        version++;
      }
      return state(items: [{'starts_on': '2026-10-01', 'version': version, 'value': saved}]);
    });
    final nursing = find.widgetWithText(CheckboxListTile, '介護保険（40〜64歳を自動判定）');
    await t.ensureVisible(nursing); await t.pumpAndSettle();
    await t.tap(nursing); await t.pumpAndSettle();
    final birth = find.widgetWithText(TextFormField, '生年月日（YYYY-MM-DD）');
    expect(birth, findsNothing);
    await tapSave(t);
    expect(find.byType(AlertDialog), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, '確認して保存').last);
    await t.pumpAndSettle();
    expect(writes, 1);
    expect(saved['nursing'], true); expect(saved['birth_date'], null);
    expect(find.textContaining('保存しました。対象の未確定給与へ反映しました。'), findsOneWidget);
  });

}
