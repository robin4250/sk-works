import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/shared/company_allowance_current_price_repository.dart';
import 'package:sk_works/features/shared/company_allowance_label_repository.dart';
import 'package:sk_works/features/payroll/company_common_allowance_repository.dart';

const definition = CompanyAllowanceLabel(id: 'item', name: '現場手当',
  unit: 'day', generation: null, origin: 'company_common',
  payrollType: 'daily', registrationVersion: 4);
CompanyAllowanceLabelSnapshot names([List<CompanyAllowanceLabel> items = const [definition]]) =>
  CompanyAllowanceLabelSnapshot(companyId: 'company', version: 4,
    legacyVersion: 2, items: items);
CompanyCommonAllowanceState prices({Map<String, dynamic> changes = const {},
    String company = 'company', int version = 4, bool empty = false}) =>
  CompanyCommonAllowanceState(companyId: company, version: version, canEdit: false,
    expectedSource: const {'legacy_version': 2}, legacyRefs: const [],
    items: empty ? [] : [{'id': 'item', 'name': '現場手当', 'unit': 'day',
      'section': 'earning', 'payroll_type': 'daily', 'amount_yen': 1200, ...changes}]);
int? amount(CompanyAllowanceLabelSnapshot labels, CompanyCommonAllowanceState? state) =>
  CompanyAllowanceCurrentPriceRepository.attachCurrentPrices(labels, state).items.single.currentRateYen;
class Labels implements CompanyAllowanceLabelSource {
  @override Future<CompanyAllowanceLabelSnapshot> read(String companyId) async => names();
}
void main() {
  test('current price and actual registered zero are distinct from unavailable', () {
    expect(amount(names(), prices()), 1200);
    expect(amount(names(), prices(changes: {'amount_yen': 0})), 0);
    expect(amount(names(), null), isNull);
    expect(amount(names(), prices(empty: true)), isNull);
  });
  test('scope, version and every definition identity must match', () {
    expect(amount(names(), prices(company: 'other')), isNull);
    expect(amount(names(), prices(version: 5)), isNull);
    for (final field in ['id', 'name', 'unit', 'section', 'payroll_type']) {
      expect(amount(names(), prices(changes: {field: 'different'})), isNull, reason: field);
    }
    expect(amount(names(), prices(changes: {'amount_yen': -1})), isNull);
  });
  test('reread picks changed current price; deletion and empty remain absent', () {
    expect(amount(names(), prices(changes: {'amount_yen': 2300})), 2300);
    final renamed = CompanyAllowanceLabel(id: 'item', name: '新名称', unit: 'day',
      generation: null, origin: 'company_common', payrollType: 'daily', registrationVersion: 4);
    expect(amount(names([renamed]), prices(changes: {'name': '新名称'})), 1200);
    expect(CompanyAllowanceCurrentPriceRepository.attachCurrentPrices(names([]), prices()).items, isEmpty);
  });
  test('legacy requires exact slot generation version and source unit', () {
    const legacy = CompanyAllowanceLabel(id: 'legacy', name: '旧手当', unit: 'day',
      generation: 3, legacySlot: 1, registrationVersion: 2, displayUnit: '日');
    final n = names([legacy]);
    CompanyCommonAllowanceState state(Map<String, dynamic> change) =>
      CompanyCommonAllowanceState(companyId: 'company', version: 4, canEdit: false,
        expectedSource: const {'legacy_version': 2}, items: const [],
        legacyRefs: [{'id': 'legacy', 'name': '旧手当', 'unit': 'day',
          'section': 'earning', 'applicability': 'all', 'slot': 1,
          'generation': 3, 'source_unit': '日', 'amount_yen': 500, ...change}]);
    expect(amount(n, state({})), 500);
    for (final change in [ {'generation': 4}, {'slot': 2}, {'source_unit': '時間'} ]) {
      expect(amount(n, state(change)), isNull);
    }
  });
  test('permission failure preserves names without a fictitious zero', () async {
    final source = CompanyAllowanceCurrentPriceRepository(labels: Labels(),
      readPrices: (_) async => throw StateError('denied'), actor: () => 'a',
      session: () => 's', sessionValid: () => true);
    final result = await source.read('company');
    expect(result.items.single.name, '現場手当');
    expect(result.items.single.currentRateYen, isNull);
  });
  test('session change during admin read rejects the entire stale result', () async {
    var token = 's';
    final source = CompanyAllowanceCurrentPriceRepository(labels: Labels(),
      readPrices: (_) async { token = 'other'; return prices(); }, actor: () => 'a',
      session: () => token, sessionValid: () => true);
    await expectLater(source.read('company'), throwsStateError);
  });
}
