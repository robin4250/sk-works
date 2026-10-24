import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/payroll_insurance_basis_reference.dart';

void main() {
  const fingerprint = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  Map<String, dynamic> row(String month, int gross, {bool finalized = true}) => {
    'statement_id': 'statement-$month', 'month': month, 'gross_pay': gross,
    'net_pay': 1, 'finalized': finalized, 'revision': 2, 'payment_date': null,
  };
  PayrollInsuranceIncomeHistoryRepository repository(List<Map<String, dynamic>> rows,
      {String responseWorker = 'worker'}) => PayrollInsuranceIncomeHistoryRepository((name, params) async {
    expect(name, 'read_worker_payroll_insurance_income_history');
    expect(params, {'p_company_id': 'company', 'p_worker_id': 'worker',
      'p_from': '2026-07-01', 'p_to': '2026-09-01'});
    return {'contract_version': 1, 'company_id': 'company', 'worker_id': responseWorker,
      'from': '2026-07-01', 'to': '2026-09-01', 'items': rows,
      'history_fingerprint': fingerprint};
  });
  Future<PayrollInsuranceIncomeHistory> read(PayrollInsuranceIncomeHistoryRepository repo) =>
      repo.read(companyId: 'company', workerId: 'worker', from: '2026-07-01', to: '2026-09-01');

  test('canonical month range is inclusive and bounded', () {
    expect(payrollReferenceMonths('2026-12-01', '2027-02-01'),
      ['2026-12-01', '2027-01-01', '2027-02-01']);
    for (final dates in [
      ['2026-13-01', '2026-14-01'], ['2026-07-02', '2026-08-01'],
      ['2026-09-01', '2026-07-01'], ['2020-01-01', '2030-01-01'],
    ]) {
      expect(() => payrollReferenceMonths(dates[0], dates[1]), throwsFormatException);
    }
  });

  test('missing months are not filled with zero, actual zero is retained, gross is used', () async {
    final history = await read(repository([row('2026-07-01', 0), row('2026-09-01', 600000)]));
    expect(history.expectedMonths, 3); expect(history.missingMonths, 1);
    expect(history.averageYen, 300000); expect(history.complete, isFalse);
    expect(history.reference(requireComplete: false).source, 'actual_available');
    expect(() => history.reference(requireComplete: true), throwsFormatException);
  });

  test('complete reference round-trips without turning average into a premium or base', () async {
    final history = await read(repository([
      row('2026-07-01', 300000), row('2026-08-01', 300001, finalized: false), row('2026-09-01', 300001),
    ]));
    expect(history.averageYen, 300001); expect(history.containsDraft, isTrue);
    final value = history.reference(requireComplete: true).toJson();
    expect(PayrollInsuranceBasisReference.fromJson(value).toJson(), value);
    expect(value.containsKey('health_base_yen'), isFalse);
    expect(value.containsKey('pension_base_yen'), isFalse);
    expect(value.containsKey('insurance_premium'), isFalse);
  });

  test('wrong worker, duplicate months and malformed monetary values fail closed', () async {
    await expectLater(read(repository([row('2026-07-01', 300000)], responseWorker: 'other')), throwsFormatException);
    await expectLater(read(repository([row('2026-07-01', 1), row('2026-07-01', 2)])), throwsFormatException);
    for (final bad in [-1, 0.5, '300000', 2147483648]) {
      await expectLater(read(repository([{...row('2026-07-01', 1), 'gross_pay': bad}])), throwsFormatException);
    }
  });

  test('manual requires no history and invalid reference cannot masquerade as complete', () {
    final manual = {'schema': 1, 'from': '2026-07-01', 'to': '2026-09-01',
      'average_monthly_income_yen': 0, 'source': 'manual', 'observed_months': 0,
      'history_fingerprint': null};
    expect(PayrollInsuranceBasisReference.fromJson(manual).averageMonthlyIncomeYen, 0);
    expect(() => PayrollInsuranceBasisReference.fromJson({...manual,
      'source': 'actual_complete', 'observed_months': 2, 'history_fingerprint': fingerprint}), throwsFormatException);
    expect(() => PayrollInsuranceBasisReference.fromJson({...manual, 'health_base_yen': 1}), throwsFormatException);
  });

  test('capability selects full reader and never falls back after its failure', () async {
    final calls = <String>[];
    final scope = {'p_company_id': 'company', 'p_worker_id': 'worker'};
    final old = {'company_id': 'company', 'worker_id': 'worker', 'items': []};
    final legacy = await readPayrollTaxConditionsWithInsuranceReference((name, params) async {
      calls.add(name); return old;
    }, scope);
    expect(legacy, old); expect(calls, ['read_worker_payroll_tax_conditions']);
    calls.clear();
    final full = {...old, 'insurance_basis_reference_contract_version': 1};
    expect(await readPayrollTaxConditionsWithInsuranceReference((name, params) async {
      calls.add(name); return full;
    }, scope), full);
    expect(calls.length, 2);
    expect(calls.last, 'read_worker_payroll_tax_conditions_with_insurance_reference');
    calls.clear();
    await expectLater(readPayrollTaxConditionsWithInsuranceReference((name, params) async {
      calls.add(name);
      if (name.endsWith('_with_insurance_reference')) throw StateError('denied or transport');
      return full;
    }, scope), throwsStateError);
    expect(calls.length, 2);
  });
}
