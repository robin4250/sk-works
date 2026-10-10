import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/domain/company_rate_contract.dart';

IncomeTaxTableReference table(int year, {String owner = 'company',
  bool official = true, bool ready = true, bool shared = false,
  IncomeTaxTableKind kind = IncomeTaxTableKind.monthly}) => IncomeTaxTableReference(
  tableId: '$year-$kind', ownerCompanyId: owner, calendarYear: year, kind: kind,
  startsOn: PayrollDate(year, 1, 1), endsBefore: PayrollDate(year + 1, 1, 1),
  pdf: Uri.parse('https://example.test/$year.pdf'), documentHash: 'fixture-$year',
  officialDocumentVerified: official, calculationRulesVerified: ready,
  commonDataApproved: shared);

void main() {
  test('future registration selects on exact civil boundary and retains old tables', () {
    final old = table(2030);
    final next = table(2031);
    final registry = IncomeTaxTableRegistry(companyId: 'company').register(old).register(next);
    expect(registry.select(date: PayrollDate(2030, 12, 31), kind: IncomeTaxTableKind.monthly), same(old));
    expect(registry.select(date: PayrollDate(2031, 1, 1), kind: IncomeTaxTableKind.monthly), same(next));
    expect(registry.select(date: PayrollDate(2032, 1, 1), kind: IncomeTaxTableKind.monthly), isNull);
    expect(registry.registered, [old, next]);
    expect(() => registry.registered.clear(), throwsUnsupportedError);
  });

  test('PDF upload and official verification alone are not calculation ready', () {
    final uploaded = table(2030, official: false, ready: false);
    final registry = IncomeTaxTableRegistry(companyId: 'company').register(uploaded);
    expect(registry.select(date: PayrollDate(2030, 5, 1), kind: IncomeTaxTableKind.monthly), isNull);
    final official = registry.recordVerification(table(2030, ready: false));
    expect(official.select(date: PayrollDate(2030, 5, 1), kind: IncomeTaxTableKind.monthly), isNull);
    final ready = official.recordVerification(table(2030));
    expect(ready.select(date: PayrollDate(2030, 5, 1), kind: IncomeTaxTableKind.monthly), isNotNull);
    expect(ready.priorVerificationStates.length, 2);
    expect(registry.registered.single, same(uploaded));
  });

  test('another company upload needs separate verified common-data approval', () {
    expect(() => IncomeTaxTableRegistry(companyId: 'company').register(
      table(2030, owner: 'other')), throwsArgumentError);
    expect(() => table(2030, owner: 'other', official: false, ready: false,
      shared: true), throwsArgumentError);
    final shared = table(2030, owner: 'other', shared: true);
    final registry = IncomeTaxTableRegistry(companyId: 'company').register(shared);
    expect(registry.select(date: PayrollDate(2030, 6, 1), kind: IncomeTaxTableKind.monthly), same(shared));
  });

  test('duplicate and overlapping schedules reject without changing registry', () {
    final registry = IncomeTaxTableRegistry(companyId: 'company').register(table(2030));
    expect(() => registry.register(table(2030, owner: 'other', shared: true)), throwsArgumentError);
    expect(registry.registered.length, 1);
    final daily = registry.register(table(2030, kind: IncomeTaxTableKind.daily));
    expect(daily.select(date: PayrollDate(2030, 4, 1), kind: IncomeTaxTableKind.bonus), isNull);
    expect(daily.registered.length, 2);
  });

  test('distinct IDs with partial overlap reject, adjacent periods succeed', () {
    IncomeTaxTableReference period(String id, int startMonth, int endMonth) =>
      IncomeTaxTableReference(tableId: id, ownerCompanyId: 'company',
        calendarYear: 2030, kind: IncomeTaxTableKind.monthly,
        startsOn: PayrollDate(2030, startMonth, 1),
        endsBefore: PayrollDate(2030, endMonth, 1),
        pdf: Uri.parse('https://example.test/$id.pdf'), documentHash: id,
        officialDocumentVerified: true, calculationRulesVerified: true);
    final first = period('first', 1, 7);
    final registry = IncomeTaxTableRegistry(companyId: 'company').register(first);
    expect(() => registry.register(period('different-overlap', 6, 9)),
      throwsArgumentError);
    final adjacent = period('adjacent', 7, 12);
    final scheduled = registry.register(adjacent);
    expect(scheduled.select(date: PayrollDate(2030, 6, 30),
      kind: IncomeTaxTableKind.monthly), same(first));
    expect(scheduled.select(date: PayrollDate(2030, 7, 1),
      kind: IncomeTaxTableKind.monthly), same(adjacent));
    expect(registry.registered, [first]);
  });

  test('verification cannot change hash, period or owner of registered PDF', () {
    final original = table(2030, official: false, ready: false);
    final registry = IncomeTaxTableRegistry(companyId: 'company').register(original);
    for (final field in ['hash', 'period', 'owner']) {
      final changed = IncomeTaxTableReference(tableId: original.tableId,
        ownerCompanyId: field == 'owner' ? 'other' : original.ownerCompanyId,
        calendarYear: original.calendarYear, kind: original.kind,
        startsOn: field == 'period' ? PayrollDate(2030, 2, 1) : original.startsOn,
        endsBefore: original.endsBefore, pdf: original.pdf,
        documentHash: field == 'hash' ? 'changed-hash' : original.documentHash,
        officialDocumentVerified: true, calculationRulesVerified: true,
        commonDataApproved: true);
      expect(() => registry.recordVerification(changed), throwsStateError,
        reason: field);
      expect(registry.registered.single, same(original));
      expect(registry.priorVerificationStates, isEmpty);
    }
  });

  test('unverified new year returns null instead of expired previous-year table', () {
    final old = table(2030);
    final future = table(2031, official: false, ready: false);
    final registry = IncomeTaxTableRegistry(companyId: 'company')
      .register(old).register(future);
    expect(registry.select(date: PayrollDate(2030, 12, 31),
      kind: IncomeTaxTableKind.monthly), same(old));
    expect(registry.select(date: PayrollDate(2031, 1, 1),
      kind: IncomeTaxTableKind.monthly), isNull);
    expect(registry.registered, [old, future]);
  });

  test('invalid civil dates and readiness without official validation reject', () {
    expect(() => PayrollDate(2030, 2, 29), throwsArgumentError);
    expect(() => PayrollDate(2032, 2, 29), returnsNormally);
    expect(() => table(2030, official: false), throwsArgumentError);
    final registry = IncomeTaxTableRegistry(companyId: 'company').register(table(2030));
    expect(() => registry.recordVerification(table(2031)), throwsStateError);
  });
}
