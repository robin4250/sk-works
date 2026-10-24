import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/payroll_unit_conditions_page.dart';
import 'package:sk_works/features/payroll/payroll_unit_conditions_repository.dart';
import 'package:sk_works/features/payroll/payroll_unit_item_editor.dart';

Map<String, dynamic> oldItem(String id, String name, {String unit = 'day'}) => {
  'id': id, 'origin': 'company_common', 'source_origin': 'company_legacy',
  'source_unit': '回', 'name': name, 'section': 'earning', 'unit': unit,
  'rate_yen': 2500, 'quantity': 0, 'amount_yen': 0,
};
const currentPc = PayrollRegisteredAllowanceName(
  key: 'company_common/new-pc', itemId: 'new-pc', name: '新PC',
  section: PayrollItemSection.earning, unit: PayrollItemUnit.day);

class _Repository implements PayrollUnitConditionsRepository {
  _Repository(this.items, {this.frozen = false, this.historyMissing = false});
  final List<Map<String, dynamic>> items;
  final bool frozen, historyMissing;
  int writes = 0, loads = 0;
  @override Future<bool> available() async => true;
  @override Future<PayrollUnitConditions> load(String company, String worker, String month) async {
    expect(company, 'company-a'); expect(worker, anyOf('worker-a', 'worker-b')); loads++;
    return PayrollUnitConditions(version: 1, month: month, canEdit: !frozen,
      items: const [], companyCommonItems: items, companyCommonFrozen: frozen,
      companyCommonHistoryMissing: historyMissing,
      companyCommonSourceJson: jsonEncode({
        'starts_on': items.isEmpty ? null : month,
        'pay_type': 'daily', 'publication_version': items.isEmpty ? null : 1, 'items': items,
      }));
  }
  @override Future<PayrollUnitConditions> save(String c, String w,
      PayrollUnitConditions current, List<PayrollUnitItemDraft> items) async {
    writes++; throw StateError('Unexpected write');
  }
  @override Future<PayrollUnitConditions> saveCommonHours(String c, String w,
      PayrollUnitConditions current, Map<String, String> hours) async {
    writes++; throw StateError('Unexpected write');
  }
}
Future<void> mount(WidgetTester t, _Repository repository, {
  List<PayrollRegisteredAllowanceName> registered = const [],
  bool loaded = true, bool unavailable = false, String worker = 'worker-a',
  PayrollItemUnit unit = PayrollItemUnit.day,
  bool embedded = false,
  List<PayrollUnitItemDraft> individualItems = const [],
  Future<void> Function()? onOpenCompanyCommonSettings,
}) async {
  t.view.physicalSize = const Size(800, 1600); t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize); addTearDown(t.view.resetDevicePixelRatio);
  final page = PayrollUnitConditionsPage(
    key: ValueKey(worker), repository: repository, companyId: 'company-a', workerId: worker,
    embedded: embedded,
    section: PayrollItemSection.earning, unit: unit,
    individualAllowanceItems: individualItems, canEditIndividualAllowances: true,
    registeredAllowanceNames: registered, registeredAllowanceNamesLoaded: loaded,
    registeredAllowanceNamesUnavailable: unavailable,
    onOpenCompanyCommonSettings: onOpenCompanyCommonSettings,
  );
  await t.pumpWidget(MaterialApp(home: embedded
      ? Scaffold(body: SingleChildScrollView(child: page)) : page));
  await t.pumpAndSettle();
}
void main() {
  testWidgets('successful empty registration does not present old payroll rows as current company settings', (t) async {
    final repository = _Repository([oldItem('old-pc', 'PC'), oldItem('old-steel', '鉄骨')]);
    await mount(t, repository);
    expect(find.byKey(const ValueKey('current-company-registration')), findsOneWidget);
    expect(find.text('この区分の会社共通手当は未登録です。'), findsOneWidget);
    expect(find.text('登録変更前の給与用手当'), findsOneWidget);
    expect(find.text('PC  ¥2500'), findsNothing);
    expect(find.text('鉄骨  ¥2500'), findsNothing);
    expect(find.text('会社の設定を給与へ自動反映'), findsNothing);
    await t.tap(find.text('登録変更前の給与用手当')); await t.pumpAndSettle();
    expect(find.text('PC  ¥2500'), findsOneWidget);
    expect(find.text('鉄骨  ¥2500'), findsOneWidget);
    expect(find.byKey(const ValueKey('common-hours-save')), findsNothing);
    expect(repository.items.first['rate_yen'], 2500); expect(repository.writes, 0);
    expect(t.takeException(), isNull);
  });
  testWidgets('employees with different payroll histories see the same newly registered company names', (t) async {
    final first = _Repository([oldItem('old-pc', 'PC')]);
    await mount(t, first, registered: [currentPc]);
    expect(find.text('新PC'), findsOneWidget);
    expect(find.text('登録変更前の給与用手当'), findsOneWidget);
    final second = _Repository([]);
    await mount(t, second, registered: [currentPc], worker: 'worker-b');
    expect(find.text('新PC'), findsOneWidget);
    expect(find.byKey(const ValueKey('current-company-registration')), findsOneWidget);
    expect(find.text('PC  ¥2500'), findsNothing);
    expect(first.writes, 0); expect(second.writes, 0); expect(t.takeException(), isNull);
  });
  for (final unavailable in [false, true]) {
    testWidgets('unknown registration unavailable=$unavailable is never inferred as empty', (t) async {
      final repository = _Repository([oldItem('old-pc', 'PC')]);
      await mount(t, repository, loaded: false, unavailable: unavailable);
      expect(find.byKey(const ValueKey('current-company-registration')), findsOneWidget);
      expect(find.text(unavailable
          ? '会社共通の登録名を確認できません。' : '会社共通の登録名を確認しています。'), findsOneWidget);
      expect(find.text('この区分の会社共通手当は未登録です。'), findsNothing);
      expect(find.text('社内共通手当'), findsOneWidget);
      expect(find.text('会社の設定を給与へ自動反映'), findsNothing);
      expect(repository.writes, 0); expect(t.takeException(), isNull);
    });
  }
  testWidgets('frozen payroll keeps saved rows even with empty current registration', (t) async {
    final repository = _Repository([oldItem('old-pc', 'PC')], frozen: true);
    await mount(t, repository);
    expect(find.byKey(const ValueKey('current-company-registration')), findsNothing);
    expect(find.text('保存済み給与の共通手当'), findsOneWidget);
    await t.tap(find.text('社内共通手当')); await t.pumpAndSettle();
    expect(find.text('PC  ¥2500'), findsOneWidget);
    expect(find.text('登録変更前の給与用手当'), findsNothing);
    expect(repository.writes, 0); expect(t.takeException(), isNull);
  });
  testWidgets('past month uses payroll conditions rather than current registration', (t) async {
    final repository = _Repository([oldItem('old-pc', 'PC')]);
    await mount(t, repository);
    await t.tap(find.byIcon(Icons.chevron_left)); await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TextButton, '月を変更')); await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('current-company-registration')), findsNothing);
    expect(find.text('社内共通手当'), findsOneWidget);
    await t.tap(find.text('社内共通手当')); await t.pumpAndSettle();
    expect(find.text('PC  ¥2500'), findsOneWidget);
    expect(repository.writes, 0); expect(t.takeException(), isNull);
  });
  testWidgets('renamed registration ID does not relabel older payroll snapshot', (t) async {
    final repository = _Repository([oldItem('new-pc', 'PC')]);
    await mount(t, repository, registered: [currentPc]);
    expect(find.text('新PC'), findsOneWidget);
    expect(find.text('登録変更前の給与用手当'), findsOneWidget);
    expect(find.text('会社共通手当の給与用条件'), findsNothing);
    await t.tap(find.text('登録変更前の給与用手当')); await t.pumpAndSettle();
    expect(find.text('PC  ¥2500'), findsOneWidget);
    expect(repository.writes, 0); expect(t.takeException(), isNull);
  });
  testWidgets('matching hourly payroll rows retain normal editing separately from registration', (t) async {
    const name = PayrollRegisteredAllowanceName(key: 'company_common/hour', itemId: 'hour',
      name: '共通時間', section: PayrollItemSection.earning, unit: PayrollItemUnit.hour);
    final repository = _Repository([oldItem('hour', '共通時間', unit: 'hour')]);
    await mount(t, repository, registered: [name], unit: PayrollItemUnit.hour);
    expect(find.text('共通時間'), findsOneWidget);
    expect(find.text('会社共通手当の給与用条件'), findsOneWidget);
    expect(find.text('登録変更前の給与用手当'), findsNothing);
    await t.tap(find.text('会社共通手当の給与用条件')); await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('common-hour-hour')), findsOneWidget);
    expect(t.widget<TextField>(find.byKey(const ValueKey('common-hour-hour'))).enabled, true);
    expect(repository.writes, 0); expect(t.takeException(), isNull);
  });
  testWidgets('retired hourly payroll rows are historical read only', (t) async {
    final repository = _Repository([oldItem('old-hour', '旧時間', unit: 'hour')]);
    await mount(t, repository, unit: PayrollItemUnit.hour);
    await t.tap(find.text('登録変更前の給与用手当')); await t.pumpAndSettle();
    expect(t.widget<TextField>(find.byKey(const ValueKey('common-hour-old-hour'))).enabled, false);
    expect(find.byKey(const ValueKey('common-hours-save')), findsNothing);
    expect(repository.writes, 0); expect(t.takeException(), isNull);
  });
  testWidgets('current registration remains visible when payroll history is missing', (t) async {
    final repository = _Repository([], historyMissing: true);
    await mount(t, repository, registered: [currentPc]);
    expect(find.text('新PC'), findsOneWidget);
    expect(find.text('社内共通手当の適用月が未登録のため、給与計算を保留しています。社内共通手当の適用月を確認してください。'), findsOneWidget);
    expect(repository.writes, 0); expect(t.takeException(), isNull);
  });
  for (final unit in PayrollItemUnit.values) {
    testWidgets('embedded $unit keeps an empty current registration panel without a payroll snapshot', (t) async {
      final repository = _Repository([]);
      await mount(t, repository, unit: unit, embedded: true);
      expect(find.byKey(const ValueKey('current-company-registration')), findsOneWidget);
      expect(find.text('現在の会社共通手当'), findsOneWidget);
      expect(find.text('この区分の会社共通手当は未登録です。'), findsOneWidget);
      expect(find.text('会社の設定を給与へ自動反映'), findsNothing);
      expect(repository.writes, 0);
      expect(t.takeException(), isNull);
    });
    testWidgets('embedded $unit displays only that unit of current registrations', (t) async {
      const hour = PayrollRegisteredAllowanceName(key: 'company_common/h', itemId: 'h',
        name: '共通時間名', section: PayrollItemSection.earning, unit: PayrollItemUnit.hour);
      const day = PayrollRegisteredAllowanceName(key: 'company_common/d', itemId: 'd',
        name: '共通日名', section: PayrollItemSection.earning, unit: PayrollItemUnit.day);
      const month = PayrollRegisteredAllowanceName(key: 'company_common/m', itemId: 'm',
        name: '共通月名', section: PayrollItemSection.earning, unit: PayrollItemUnit.month);
      const names = [hour, day, month];
      final repository = _Repository([]);
      await mount(t, repository, unit: unit, embedded: true, registered: names);
      for (final name in names) {
        expect(find.text(name.name), name.unit == unit ? findsOneWidget : findsNothing);
      }
      expect(find.text('退勤の実勤務時間との連動は準備中です。登録名の表示だけでは給与へ反映されません。'),
          unit == PayrollItemUnit.hour ? findsOneWidget : findsNothing);
      expect(repository.writes, 0);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('same-name company and individual allowances remain visibly distinct without copying IDs', (t) async {
    const personal = PayrollUnitItemDraft(id: 'worker-allowance-slot-1',
      section: PayrollItemSection.earning, unit: PayrollItemUnit.day,
      name: '新PC', rate: '3000', source: 'selected_allowance_days');
    final repository = _Repository([]);
    await mount(t, repository, registered: [currentPc], individualItems: [personal]);
    expect(find.text('現在の会社共通手当'), findsOneWidget);
    expect(find.text('個別手当（この社員だけ）'), findsOneWidget);
    expect(find.byKey(const ValueKey('current-company-registered-company_common/new-pc')), findsOneWidget);
    final own = t.widget<TextField>(find.byKey(const ValueKey('worker-allowance-slot-1-name')));
    expect(own.controller!.text, '新PC');
    expect(own.enabled, true);
    final editor = t.widget<PayrollUnitItemEditor>(find.byType(PayrollUnitItemEditor));
    expect(editor.initialItems.map((item) => item.id), ['worker-allowance-slot-1']);
    expect(editor.initialItems.any((item) => item.id == 'new-pc'), false);
    expect(repository.writes, 0);
    expect(t.takeException(), isNull);
  });
  testWidgets('company editing is delegated to the company settings action without saving individual values', (t) async {
    final repository = _Repository([]);
    var opened = 0;
    await mount(t, repository, registered: [currentPc],
      onOpenCompanyCommonSettings: () async { opened++; });
    await t.tap(find.byKey(const ValueKey('open-company-common-settings')));
    await t.pumpAndSettle();
    expect(opened, 1);
    expect(repository.writes, 0);
    expect(t.takeException(), isNull);
  });

  testWidgets('legacy ID and slot correspondence retains the original payroll display de-duplication', (t) async {
    const legacy = PayrollRegisteredAllowanceName(key: 'company_legacy/legacy-pc',
      itemId: 'legacy-pc', legacySlot: 1, name: 'PC',
      section: PayrollItemSection.earning, unit: PayrollItemUnit.day);
    const personal = PayrollUnitItemDraft(id: 'worker-allowance-slot-1',
      section: PayrollItemSection.earning, unit: PayrollItemUnit.day,
      name: 'PC', rate: '2500', source: 'selected_allowance_days');
    final repository = _Repository([oldItem('legacy-pc', 'PC')]);
    await mount(t, repository, registered: [legacy], individualItems: [personal]);
    expect(find.byKey(const ValueKey('current-company-registered-company_legacy/legacy-pc')), findsOneWidget);
    expect(find.byKey(const ValueKey('worker-allowance-slot-1-name')), findsOneWidget);
    expect(find.text('会社共通手当の給与用条件'), findsNothing);
    expect(find.text('登録変更前の給与用手当'), findsNothing);
    final editor = t.widget<PayrollUnitItemEditor>(find.byType(PayrollUnitItemEditor));
    expect(editor.initialItems.map((item) => item.id), ['worker-allowance-slot-1']);
    expect(repository.writes, 0);
    expect(t.takeException(), isNull);
  });
  testWidgets('same name with a different legacy slot does not suppress a distinct payroll item', (t) async {
    const legacy = PayrollRegisteredAllowanceName(key: 'company_legacy/other-pc',
      itemId: 'other-pc', legacySlot: 2, name: 'PC',
      section: PayrollItemSection.earning, unit: PayrollItemUnit.day);
    const personal = PayrollUnitItemDraft(id: 'worker-allowance-slot-1',
      section: PayrollItemSection.earning, unit: PayrollItemUnit.day,
      name: 'PC', rate: '3000', source: 'selected_allowance_days');
    final repository = _Repository([oldItem('other-pc', 'PC')]);
    await mount(t, repository, registered: [legacy], individualItems: [personal]);
    expect(find.text('会社共通手当の給与用条件'), findsOneWidget);
    await t.tap(find.text('会社共通手当の給与用条件')); await t.pumpAndSettle();
    expect(find.text('PC  ¥2500'), findsOneWidget);
    expect(t.widget<TextField>(find.byKey(const ValueKey('worker-allowance-slot-1-rate'))).controller!.text, '3000');
    expect(repository.writes, 0);
    expect(t.takeException(), isNull);
  });

}
