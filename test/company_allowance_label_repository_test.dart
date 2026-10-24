import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/shared/company_allowance_label_repository.dart';

const company = '10000000-0000-0000-0000-000000000001';
Map<String, dynamic> common(int index, String type, String unit) => {
  'id': '20000000-0000-0000-0000-${index.toString().padLeft(12, '0')}',
  'name': '$type/$unit', 'origin': 'company_common', 'payroll_type': type,
  'section': unit == 'month' ? 'deduction' : 'earning', 'unit': unit,
  'display_unit': unit, 'legacy_slot': null, 'generation': null, 'registration_version': 3,
};
Map<String, dynamic> labels() => {'contract_version': 1, 'company_id': company,
  'registration_scope': 'current', 'source_versions': {'legacy_version': 2, 'common_version': 3},
  'items': [
    {'id': '30000000-0000-0000-0000-000000000001', 'name': ' 会社の登録名 ',
      'origin': 'company_legacy', 'payroll_type': 'all', 'section': 'earning',
      'unit': 'day', 'display_unit': '回', 'legacy_slot': 1, 'generation': 1,
      'registration_version': 2},
    for (var i = 0; i < 3; i++)
      for (var j = 0; j < 3; j++) common(10 + i * 3 + j,
        const ['daily', 'hourly', 'monthly'][i], const ['hour', 'day', 'month'][j]),
  ]};
void main() {
  test('all registered units and salary types read from one explicit company without copying prices', () async {
    final calls = <String>[];
    final source = SupabaseCompanyAllowanceLabelRepository.forTesting(
      actor: () => 'actor', sessionKey: () => 'session', invoke: (name, params) async {
        calls.add(name); expect(params, {'p_company_id': company}); return labels();
      });
    final value = await source.read(company);
    expect(calls, ['read_company_registered_allowance_labels']);
    expect(value.companyId, company); expect(value.version, 3); expect(value.legacyVersion, 2);
    expect(value.items, hasLength(10));
    expect(value.items.first.name, ' 会社の登録名 ');
    expect(value.items.first.unit, 'day'); expect(value.items.first.displayUnit, '回');
    expect(value.items.first.legacySlot, 1); expect(value.items.every((x) => x.selectable), isTrue);
    expect(value.items.where((x) => x.origin == 'company_common').map((x) => x.unit).toSet(), {'hour', 'day', 'month'});
    expect(() => value.items.clear(), throwsUnsupportedError);
  });
  test('unadopted legacy labels remain visible but cannot fabricate a stable selection', () {
    final raw = labels(); (raw['source_versions'] as Map)['legacy_version'] = null;
    final first = (raw['items'] as List).first as Map;
    first['id'] = null; first['generation'] = null; first['registration_version'] = null;
    final value = CompanyAllowanceLabelSnapshot.parse(raw, company);
    expect(value.items.first.name, ' 会社の登録名 ');
    expect(value.items.first.selectable, isFalse); expect(value.items.first.id, isNull);
    expect(value.items.last.selectable, isTrue);
  });
  test('wrong scope, duplicate source and malformed or mismatched registration metadata refuse', () {
    expect(() => CompanyAllowanceLabelSnapshot.parse(labels(), 'another'), throwsFormatException);
    final duplicate = labels(); (duplicate['items'] as List)[1] = (duplicate['items'] as List).first;
    expect(() => CompanyAllowanceLabelSnapshot.parse(duplicate, company), throwsFormatException);
    final mismatch = labels(); ((mismatch['items'] as List)[1] as Map)['registration_version'] = 2;
    expect(() => CompanyAllowanceLabelSnapshot.parse(mismatch, company), throwsFormatException);
    final unit = labels(); ((unit['items'] as List)[1] as Map)['unit'] = 'guessed-eight-hours';
    expect(() => CompanyAllowanceLabelSnapshot.parse(unit, company), throwsFormatException);
  });
  test('actor or session change drops names and no write or old-three-slot fallback is called', () async {
    for (final changeActor in [true, false]) {
      var actor = 'actor', session = 'session';
      final source = SupabaseCompanyAllowanceLabelRepository.forTesting(
        actor: () => actor, sessionKey: () => session, invoke: (name, params) async {
          expect(name, 'read_company_registered_allowance_labels');
          if (changeActor) { actor = 'other'; } else { session = 'new-session'; }
          return labels();
        });
      await expectLater(source.read(company), throwsStateError);
    }
  });
}
