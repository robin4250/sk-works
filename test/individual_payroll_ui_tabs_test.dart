import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/individual_payroll_settings_page.dart';
import 'package:sk_works/features/payroll/individual_payroll_settings_repository.dart';
import 'package:sk_works/features/payroll/resident_tax_capability.dart';
import 'package:sk_works/widgets/rate_formula_editor_card.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Repository extends IndividualPayrollSettingsRepository {
  _Repository(this.client, {this.edit = true, this.initial}) : super.forTesting(client);
  final SupabaseClient client;
  final bool edit;
  final Map<String, dynamic>? initial;
  Map<String, dynamic>? saved;
  @override
  Future<IndividualPayrollWorkspace> loadWorkspace() async =>
      IndividualPayrollWorkspace(
        canView: true,
        canEdit: edit,
        isAdmin: edit,
        workers: const [IndividualPayrollWorker(id: 'worker-a', name: '社員A')],
      );
  @override
  Future<bool> supportsPaidLeaveWages() async => false;
  @override
  Future<ResidentTaxCapability> residentTaxCapability() async =>
      ResidentTaxCapability.legacy;
  @override
  Future<IndividualPayrollSetting> loadSetting(String workerId) async =>
      IndividualPayrollSetting(
        workerId: workerId,
        updatedAt: DateTime(2026, 10, 12, 7, 30),
        values:
            saved ?? initial ??
            {
              'pay_type': 'daily',
              'day_daily': 10000,
              'day_overtime': 2000,
              'night_early': 2300,
              'social_insurance_monthly': 12345,
              'resident_tax_monthly': 6789,
              'custom_earnings': [
                {'name': '既存支給', 'amount_yen': 100},
              ],
              'custom_deductions': [
                {'name': '既存控除', 'amount_yen': 200},
              ],
            },
      );
  @override
  Future<void> saveSetting({
    required String workerId,
    required Map<String, dynamic> values,
  }) async {
    expect(workerId, 'worker-a');
    saved = Map.of(values);
  }
}

void main() {
  late SupabaseClient client;
  setUp(
    () => client = SupabaseClient(
      'https://synthetic.invalid',
      'synthetic-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    ),
  );
  tearDown(() async => client.dispose());

  testWidgets('saving one allowance preserves existing tax, resident tax and every legacy insurance row', (t) async {
    final insurance = [
      {'name': '健康保険料', 'amount_yen': 5100},
      {'name': '厚生年金保険', 'amount_yen': 9000},
      {'name': '雇用保険料', 'amount_yen': 1200},
      {'name': '介護保険料', 'amount_yen': 0},
    ];
    final repository = _Repository(client, initial: {
      'pay_type': 'daily', 'day_daily': 20000,
      'income_tax_monthly': 6300, 'resident_tax_monthly': 12500,
      'social_insurance_monthly': 0,
      'custom_earnings': [{'name': '個別手当', 'amount_yen': 100}],
      'custom_deductions': insurance,
      'rate_formula': {'paid_leave_daily_yen': 9000},
    });
    await t.pumpWidget(MaterialApp(home: IndividualPayrollSettingsPage(repository: repository)));
    await t.pumpAndSettle();
    final allowance = find.widgetWithText(TextFormField, '支給1 金額');
    await t.ensureVisible(allowance);
    await t.enterText(allowance, '200');
    FocusManager.instance.primaryFocus?.unfocus();
    await t.tap(find.widgetWithText(FilledButton, '登録'));
    await t.pumpAndSettle();
    await t.tap(find.text('確定して保存'));
    await t.pumpAndSettle();
    expect(repository.saved!['custom_earnings'], [{'name': '個別手当', 'amount_yen': 200}]);
    expect(repository.saved!['custom_deductions'], insurance);
    expect(repository.saved!['income_tax_monthly'], 6300);
    expect(repository.saved!['resident_tax_monthly'], 12500);
    expect(repository.saved!['social_insurance_monthly'], 0);
    expect((repository.saved!['rate_formula'] as Map)['paid_leave_daily_yen'], 9000);
    expect(repository.saved!.keys, isNot(contains('company_common')));
    expect(repository.saved!.keys, isNot(contains('unit_conditions')));
    expect(repository.saved!.keys, isNot(contains('unit_quantities')));
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'tabs retain raw input, footer adds to selected section and saves both',
    (tester) async {
      final repository = _Repository(client);
      await tester.pumpWidget(
        MaterialApp(
          home: IndividualPayrollSettingsPage(repository: repository),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('残業 直接入力'), findsNothing);
      expect(find.textContaining('最終更新日：2026/10/12'), findsOneWidget);
      expect(find.text('時間単位'), findsOneWidget);
      expect(find.text('日単位'), findsOneWidget);
      expect(find.text('月単位'), findsOneWidget);
      final earningName = find.widgetWithText(TextFormField, '支給1 名称');
      await tester.ensureVisible(earningName);
      await tester.enterText(earningName, '未保存支給');
      await tester.enterText(
        find.widgetWithText(TextFormField, '支給1 金額'),
        '00321',
      );
      await tester.ensureVisible(find.text('時間単位'));
      await tester.tap(find.text('時間単位'));
      await tester.pumpAndSettle();
      expect(earningName, findsNothing);
      await tester.tap(find.text('月単位'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(earningName).controller!.text, '未保存支給');
      final tabs = find.byType(SegmentedButton<bool>);
      await tester.ensureVisible(tabs);
      await tester.tap(find.descendant(of: tabs, matching: find.text('控除')));
      await tester.pumpAndSettle();
      expect(earningName, findsNothing);
      await tester.tap(find.widgetWithText(OutlinedButton, '追加'));
      await tester.pumpAndSettle();
      final deductionName = find.widgetWithText(TextFormField, '控除2 名称');
      expect(deductionName.hitTestable(), findsOneWidget);
      await tester.enterText(deductionName, '追加控除');
      await tester.ensureVisible(find.widgetWithText(TextFormField, '控除2 金額'));
      await tester.enterText(
        find.widgetWithText(TextFormField, '控除2 金額'),
        '00456',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.ensureVisible(tabs);
      await tester.tap(find.descendant(of: tabs, matching: find.text('支給')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(earningName);
      expect(
        tester.widget<TextFormField>(earningName).controller!.text,
        '未保存支給',
      );
      expect(
        tester
            .widget<TextFormField>(find.widgetWithText(TextFormField, '支給1 金額'))
            .controller!
            .text,
        '00321',
      );
      await tester.tap(find.widgetWithText(FilledButton, '登録'));
      await tester.pumpAndSettle();
      expect(repository.saved, isNull);
      await tester.tap(find.text('確定して保存'));
      await tester.pumpAndSettle();
      expect(repository.saved!['custom_earnings'], [
        {'name': '未保存支給', 'amount_yen': 321},
      ]);
      expect(repository.saved!['custom_deductions'], [
        {'name': '既存控除', 'amount_yen': 200},
        {'name': '追加控除', 'amount_yen': 456},
      ]);
      expect(repository.saved!['social_insurance_monthly'], 12345);
      expect(repository.saved!['resident_tax_monthly'], 6789);
      expect(repository.saved!['day_overtime'], 2000);
      expect(repository.saved!['night_early'], 2300);
      expect(tester.takeException(), isNull);
    },
  );


  testWidgets(
    'daily legacy allowances stay daily and monthly optional rows migrate once',
    (tester) async {
      final repository = _Repository(client, initial: {
        'pay_type': 'daily', 'day_daily': 10000,
        'allowance_name_1': 'PC', 'allowance_1': 2500,
        'allowance_name_2': '鉄骨', 'allowance_2': 2500,
        'family_monthly': 2000, 'transport_monthly': 3000,
        'custom_earnings': [
          {'name': '家族手当', 'amount_yen': 1000},
          {'name': '交通費', 'amount_yen': 500},
        ],
        'custom_deductions': <Map<String, dynamic>>[],
      });
      await tester.pumpWidget(MaterialApp(
        home: IndividualPayrollSettingsPage(repository: repository),
      ));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, '手当1 名称'), findsNothing);
      expect(find.text('家族手当・月額（既存設定）'), findsNothing);
      expect(find.text('交通費・月額'), findsNothing);
      final familyName = find.widgetWithText(TextFormField, '支給1 名称');
      final familyAmount = find.widgetWithText(TextFormField, '支給1 金額');
      final transportName = find.widgetWithText(TextFormField, '支給2 名称');
      final transportAmount = find.widgetWithText(TextFormField, '支給2 金額');
      expect(tester.widget<TextFormField>(familyName).controller!.text, '家族手当');
      expect(tester.widget<TextFormField>(familyAmount).controller!.text, '3000');
      expect(tester.widget<TextFormField>(transportName).controller!.text, '交通費');
      expect(tester.widget<TextFormField>(transportAmount).controller!.text, '3500');
      expect(repository.saved, isNull); // Reading alone never writes settings.

      await tester.ensureVisible(find.text('日単位'));
      await tester.tap(find.text('日単位'));
      await tester.pumpAndSettle();
      expect(familyName, findsNothing);
      final allowanceName = find.byKey(const ValueKey('worker-allowance-slot-1-name'));
      final allowanceAmount = find.byKey(const ValueKey('worker-allowance-slot-1-rate'));
      await tester.ensureVisible(allowanceName);
      expect(tester.widget<TextField>(allowanceName).controller!.text, 'PC');
      expect(tester.widget<TextField>(allowanceAmount).controller!.text, '2500');
      await tester.enterText(allowanceAmount, '2600');
      expect(find.text('手当1〜3を登録'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, '登録'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('確定して保存'));
      await tester.pumpAndSettle();
      expect(repository.saved!['allowance_1'], 2600);
      expect(repository.saved!['allowance_name_1'], 'PC');
      expect(repository.saved!['allowance_2'], 2500);
      expect(repository.saved!['family_monthly'], 0);
      expect(repository.saved!['transport_monthly'], 0);
      expect(repository.saved!['custom_earnings'], [
        {'name': '家族手当', 'amount_yen': 3000},
        {'name': '交通費', 'amount_yen': 3500},
      ]);
      await tester.ensureVisible(find.text('月単位'));
      await tester.tap(find.text('月単位'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, '手当1 名称'), findsNothing);
      expect(tester.widget<TextFormField>(familyAmount).controller!.text, '3000');
      expect(tester.widget<TextFormField>(transportAmount).controller!.text, '3500');

      // These are ordinary editable/deletable monthly entries after reload.
      await tester.ensureVisible(transportName);
      await tester.enterText(transportName, '通勤補助');
      final remove = find.widgetWithText(TextButton, 'この支給を削除').first;
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '登録'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('確定して保存'));
      await tester.pumpAndSettle();
      expect(repository.saved!['custom_earnings'], [
        {'name': '通勤補助', 'amount_yen': 3500},
      ]);
      expect(repository.saved!['family_monthly'], 0);
      expect(repository.saved!['transport_monthly'], 0);
      expect(find.text('家族手当'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '320px large text keeps footer visible and viewer cannot mutate',
    (tester) async {
      tester.view.resetPhysicalSize();
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: IndividualPayrollSettingsPage(
            repository: _Repository(client, edit: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '追加'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '登録'))
            .onPressed,
        isNull,
      );
      final scroll = tester
          .widget<SingleChildScrollView>(
            find.byType(SingleChildScrollView).first,
          )
          .controller!;
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(FilledButton, '登録').hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compact monthly detail fold keeps its saved base and manual override',
    (tester) async {
      RateFormulaDraft? value;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RateFormulaEditorCard(
                title: '単価',
                compact: true,
                initialPayType: 'monthly',
                initialMonthlySalaryYen: 350000,
                initialBaseRateYen: 14000,
                initialFormula: const {},
                initialOverrides: const {'overtime': 2400},
                enabled: true,
                onChanged: (draft) => value = draft,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('残業 直接入力'), findsNothing);
      expect(find.text('計算用 1日基本ベース'), findsNothing);
      expect(value!.monthlySalaryYen, 350000);
      expect(value!.baseRateYen, 14000);
      expect(value!.effective('overtime'), 2400);
      await tester.tap(find.text('詳細設定'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, '計算用 1日基本ベース'),
        '014567',
      );
      await tester.tap(find.text('詳細設定'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('詳細設定'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, '計算用 1日基本ベース'))
            .controller!
            .text,
        '014567',
      );
      expect(value!.effective('overtime'), 2400);
      expect(tester.takeException(), isNull);
    },
  );
}

