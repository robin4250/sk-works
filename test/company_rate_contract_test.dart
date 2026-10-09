import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/domain/company_rate_contract.dart';

RateShares shares(int employee, int employer) => RateShares(
  total: PercentRate(employee + employer), employee: PercentRate(employee),
  employer: PercentRate(employer));

CompanyRateSetting setting(String id, int employee, int employer) => CompanyRateSetting(
  itemId: id, kind: CompanyRateKind.employmentInsurance, label: id,
  shares: shares(employee, employer), insuranceMonth: RateMonth(2030, 4),
  payrollDeductionMonth: RateMonth(2030, 5), paymentMonth: RateMonth(2030, 6),
  source: RateSource(url: Uri.parse('https://example.test/official.pdf'),
    publisher: 'Fixture only', documentHash: 'fixture-document-hash',
    checkedAt: DateTime.utc(2030, 3), applicability: {'business': 'fixture'}),
  version: 0);

void main() {
  test('fixed precision preserves unequal explicit shares without division', () {
    final value = shares(123456, 654321);
    expect(value.total.millionthsOfPercent, 777777);
    expect(value.employee.millionthsOfPercent, 123456);
    expect(value.employer.millionthsOfPercent, 654321);
    expect(() => PercentRate(-1), throwsArgumentError);
    expect(() => PercentRate(100000001), throwsArgumentError);
    expect(() => RateShares(total: PercentRate(10), employee: PercentRate(4),
      employer: PercentRate(5)), throwsArgumentError);
  });

  test('candidate retrieval cannot change current settings or history', () {
    final current = setting('employment', 100, 200);
    final state = CompanyRateState(settings: {'employment': current});
    final candidate = OfficialRateCandidate(candidateId: 'document-v2',
      proposed: setting('employment', 150, 250), sourceAndCompanyScopeVerified: true);
    expect(candidate.proposed.shares.employee.millionthsOfPercent, 150);
    expect(state.settings['employment'], same(current));
    expect(state.history, isEmpty);
    expect(() => state.settings.clear(), throwsUnsupportedError);
  });

  test('selected application is immutable and records actor, time and both shares', () {
    final state = CompanyRateState(settings: {
      'employment': setting('employment', 100, 200),
      'untouched': setting('untouched', 300, 400),
    });
    final candidate = OfficialRateCandidate(candidateId: 'document-v2',
      proposed: setting('employment', 150, 250), sourceAndCompanyScopeVerified: true);
    final applied = state.apply(candidate: candidate,
      confirmation: RateApplyConfirmation(itemId: 'employment',
        candidateId: 'document-v2', expectedVersion: 0, ratesMonthsAndSourceReviewed: true),
      actorId: 'administrator', changedAt: DateTime.utc(2030, 3, 2));
    expect(state.settings['employment']!.shares.employee.millionthsOfPercent, 100);
    expect(state.history, isEmpty);
    expect(applied.settings['untouched'], same(state.settings['untouched']));
    expect(applied.settings['employment']!.version, 1);
    final change = applied.history.single;
    expect(change.before.shares, shares(100, 200));
    expect(change.after.shares, shares(150, 250));
    expect(change.actorId, 'administrator');
    expect(change.changedAt, DateTime.utc(2030, 3, 2));
    expect(change.after.payrollDeductionMonth, RateMonth(2030, 5));
    expect(change.after.paymentMonth, RateMonth(2030, 6));
    expect(() => applied.history.clear(), throwsUnsupportedError);
  });

  test('unconfirmed, unverified, stale, wrong-item and anonymous apply reject atomically', () {
    final state = CompanyRateState(settings: {'employment': setting('employment', 100, 200)});
    for (final scenario in ['unconfirmed', 'unverified', 'stale', 'wrong-item',
      'wrong-candidate', 'anonymous']) {
      final candidate = OfficialRateCandidate(candidateId: 'document-v2',
        proposed: setting('employment', 150, 250),
        sourceAndCompanyScopeVerified: scenario != 'unverified');
      expect(() => state.apply(candidate: candidate,
        confirmation: RateApplyConfirmation(
          itemId: scenario == 'wrong-item' ? 'missing' : 'employment',
          candidateId: scenario == 'wrong-candidate' ? 'other' : 'document-v2',
          expectedVersion: scenario == 'stale' ? 1 : 0,
          ratesMonthsAndSourceReviewed: scenario != 'unconfirmed'),
        actorId: scenario == 'anonymous' ? ' ' : 'administrator',
        changedAt: DateTime.utc(2030, 3, 2)), throwsStateError, reason: scenario);
      expect(state.history, isEmpty);
      expect(state.settings['employment']!.version, 0);
    }
  });

  test('PDF registration is independent from verified income tax calculation', () {
    final table = IncomeTaxTableReference(tableId: 'fixture-table', calendarYear: 2030,
      startsOn: DateTime.utc(2030), endsBefore: DateTime.utc(2031),
      pdf: Uri.parse('https://example.test/table.pdf'), documentHash: 'fixture-hash',
      calculationRulesVerified: false);
    expect(table.calculationRulesVerified, isFalse);
    expect(() => RateMonth(2030, 13), throwsArgumentError);
  });
}
