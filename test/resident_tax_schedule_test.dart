import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/domain/resident_tax_schedule.dart';

void main() {
  final now = DateTime.utc(2026, 10, 9);
  ResidentTaxSchedule empty() => ResidentTaxSchedule.empty(companyId: 'company-a', workerId: 'worker-a');
  ResidentTaxEntry entry(int month, int yen) => ResidentTaxEntry(startMonth: ResidentTaxMonth(2026, month), monthlyAmountYen: yen);
  ResidentTaxSchedule add(ResidentTaxSchedule state, int month, int yen) => state.register(
    companyId: 'company-a', workerId: 'worker-a', expectedVersion: state.version,
    entry: entry(month, yen), actorId: 'admin-a', changedAt: now,
  );
  ResidentTaxSelection select(ResidentTaxSchedule state, int month) => state.select(
    companyId: 'company-a', workerId: 'worker-a', payrollMonth: ResidentTaxMonth(2026, month),
  );
  test('unregistered, before start, and explicit active zero are distinct', () {
    expect(select(empty(), 5).status, ResidentTaxSelectionStatus.unregistered);
    final state = add(empty(), 6, 0);
    expect(select(state, 5).status, ResidentTaxSelectionStatus.beforeFirstStart);
    expect(select(state, 5).monthlyAmountYen, isNull);
    expect(select(state, 6).status, ResidentTaxSelectionStatus.active);
    expect(select(state, 6).monthlyAmountYen, 0);
  });
  test('future and out of order registrations select latest applicable start', () {
    var state = add(empty(), 12, 13000);
    state = add(state, 6, 10000);
    state = add(state, 9, 11000);
    expect(select(state, 6).monthlyAmountYen, 10000);
    expect(select(state, 8).monthlyAmountYen, 10000);
    expect(select(state, 9).monthlyAmountYen, 11000);
    expect(select(state, 11).monthlyAmountYen, 11000);
    expect(select(state, 12).monthlyAmountYen, 13000);
    expect(state.select(companyId: 'company-a', workerId: 'worker-a', payrollMonth: ResidentTaxMonth(2027, 1)).monthlyAmountYen, 13000);
  });
  test('explicit amendments preserve old state and actor/time before-after history', () {
    final original = add(empty(), 6, 10000);
    final corrected = original.amend(companyId: 'company-a', workerId: 'worker-a', expectedVersion: 1,
        entry: entry(6, 12000), actorId: 'admin-b', changedAt: now.add(const Duration(hours: 1)));
    expect(original.entries.single.monthlyAmountYen, 10000);
    expect(corrected.entries.single.monthlyAmountYen, 12000);
    expect(corrected.version, 2);
    expect(corrected.history.first.before, isNull);
    expect(corrected.history.last.before?.monthlyAmountYen, 10000);
    expect(corrected.history.last.after.monthlyAmountYen, 12000);
    expect(corrected.history.last.actorId, 'admin-b');
    expect(corrected.history.last.changedAtUtc, now.add(const Duration(hours: 1)));
    expect(corrected.history.last.version, 2);
    expect(() => corrected.history.clear(), throwsUnsupportedError);
    expect(() => corrected.entries.clear(), throwsUnsupportedError);
  });
  test('duplicates, stale version, missing amendment and scope mismatch reject', () {
    final state = add(empty(), 6, 10000);
    expect(() => add(state, 6, 20000), throwsStateError);
    expect(() => state.amend(companyId: 'company-a', workerId: 'worker-a', expectedVersion: 0,
        entry: entry(6, 20000), actorId: 'admin-a', changedAt: now), throwsStateError);
    expect(() => state.amend(companyId: 'company-a', workerId: 'worker-a', expectedVersion: 1,
        entry: entry(7, 20000), actorId: 'admin-a', changedAt: now), throwsStateError);
    expect(() => state.register(companyId: 'company-b', workerId: 'worker-a', expectedVersion: 1,
        entry: entry(7, 20000), actorId: 'admin-a', changedAt: now), throwsStateError);
    expect(() => state.select(companyId: 'company-a', workerId: 'worker-b', payrollMonth: ResidentTaxMonth(2026, 6)), throwsStateError);
    expect(state.version, 1);
    expect(state.history, hasLength(1));
  });
  test('month, amount and audit identity reject invalid values', () {
    expect(() => ResidentTaxMonth(2026, 0), throwsRangeError);
    expect(() => ResidentTaxMonth(2026, 13), throwsRangeError);
    expect(() => ResidentTaxMonth(0, 1), throwsRangeError);
    expect(() => entry(6, -1), throwsRangeError);
    expect(() => entry(6, ResidentTaxSchedule.maxExactInteger + 1), throwsRangeError);
    expect(entry(6, ResidentTaxSchedule.maxExactInteger).monthlyAmountYen, ResidentTaxSchedule.maxExactInteger);
    expect(() => empty().register(companyId: 'company-a', workerId: 'worker-a', expectedVersion: 0,
        entry: entry(6, 1), actorId: '', changedAt: now), throwsArgumentError);
    expect(() => ResidentTaxSchedule.empty(companyId: ' ', workerId: 'worker-a'), throwsArgumentError);
  });
}
