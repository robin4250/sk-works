/// Reference income is advisory. It is never converted into an insurance base.
class PayrollInsuranceBasisReference {
  const PayrollInsuranceBasisReference({
    required this.from,
    required this.to,
    required this.averageMonthlyIncomeYen,
    required this.source,
    required this.observedMonths,
    this.historyFingerprint,
  });

  final String from, to, source;
  final int averageMonthlyIncomeYen, observedMonths;
  final String? historyFingerprint;

  static PayrollInsuranceBasisReference fromJson(dynamic raw) {
    if (raw is! Map || raw['schema'] != 1 ||
        raw.keys.any((key) => !const {'schema', 'from', 'to',
          'average_monthly_income_yen', 'source', 'observed_months',
          'history_fingerprint'}.contains(key))) {
      throw const FormatException('平均月収の保存形式を確認できません');
    }
    final from = raw['from'], to = raw['to'];
    if (from is! String || to is! String) {
      throw const FormatException('平均月収の対象期間を確認できません');
    }
    final months = payrollReferenceMonths(from, to);
    final average = raw['average_monthly_income_yen'];
    final count = raw['observed_months'];
    final source = raw['source'];
    final fingerprint = raw['history_fingerprint'];
    if (average is! int || average < 0 || average > 2147483647 ||
        count is! int || count < 0 || count > months.length ||
        !const ['manual', 'actual_available', 'actual_complete'].contains(source) ||
        (source == 'manual' && (count != 0 || fingerprint != null)) ||
        (source != 'manual' && (count < 1 || fingerprint is! String ||
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(fingerprint))) ||
        (source == 'actual_complete' && count != months.length)) {
      throw const FormatException('平均月収の根拠を確認できません');
    }
    return PayrollInsuranceBasisReference(from: from, to: to,
      averageMonthlyIncomeYen: average, source: source as String,
      observedMonths: count, historyFingerprint: fingerprint as String?);
  }

  Map<String, dynamic> toJson() => {
    'schema': 1, 'from': from, 'to': to,
    'average_monthly_income_yen': averageMonthlyIncomeYen,
    'source': source, 'observed_months': observedMonths,
    'history_fingerprint': historyFingerprint,
  };
}

List<String> payrollReferenceMonths(String from, String to) {
  final pattern = RegExp(r'^20\d{2}-(0[1-9]|1[0-2])-01$');
  if (!pattern.hasMatch(from) || !pattern.hasMatch(to)) {
    throw const FormatException('対象年月をYYYY-MMで入力してください');
  }
  final start = DateTime.parse(from), end = DateTime.parse(to);
  final count = (end.year - start.year) * 12 + end.month - start.month + 1;
  if (count < 1 || count > 120) {
    throw const FormatException('対象期間は開始月から120か月以内で指定してください');
  }
  return List.generate(count, (index) {
    final month = DateTime(start.year, start.month + index);
    return '${month.year}-${month.month.toString().padLeft(2, '0')}-01';
  }, growable: false);
}

class PayrollInsuranceIncomeMonth {
  const PayrollInsuranceIncomeMonth({required this.statementId,
    required this.month, required this.grossPay, required this.finalized,
    required this.revision, this.paymentDate});
  final String statementId, month;
  final String? paymentDate;
  final int grossPay, revision;
  final bool finalized;
}

class PayrollInsuranceIncomeHistory {
  const PayrollInsuranceIncomeHistory({required this.from, required this.to,
    required this.items, required this.fingerprint});
  final String from, to, fingerprint;
  final List<PayrollInsuranceIncomeMonth> items;
  int get expectedMonths => payrollReferenceMonths(from, to).length;
  int get missingMonths => expectedMonths - items.length;
  bool get complete => missingMonths == 0;
  bool get containsDraft => items.any((row) => !row.finalized);
  int? get averageYen => items.isEmpty ? null :
      (items.fold<int>(0, (sum, row) => sum + row.grossPay) / items.length).round();

  PayrollInsuranceBasisReference reference({required bool requireComplete}) {
    if (averageYen == null || (requireComplete && !complete)) {
      throw const FormatException('対象期間の実績が揃っていません');
    }
    return PayrollInsuranceBasisReference(from: from, to: to,
      averageMonthlyIncomeYen: averageYen!,
      source: requireComplete ? 'actual_complete' : 'actual_available',
      observedMonths: items.length, historyFingerprint: fingerprint);
  }
}

/// Server declares the canonical personal UID birthday source, never raw DOB.
/// Missing support is preparation, unknown declarations are errors.
String? payrollBirthSource(Map raw) {
  if (!raw.containsKey('birth_source')) return null;
  final source = raw['birth_source'];
  if (source != 'personal_uid_v1' && source != 'company_worker_unlinked_v1') {
    throw const FormatException('誕生日の参照元を確認できません');
  }
  return source as String;
}
bool payrollUsesPersonalBirthSource(Map raw) => payrollBirthSource(raw) == 'personal_uid_v1';

typedef PayrollInsuranceBasisRpc = Future<dynamic> Function(
  String name, Map<String, dynamic> parameters);

/// Old readers retain their old value shape. A declared capability requires
/// the full reader; failure must never silently erase the saved reference.
Future<dynamic> readPayrollTaxConditionsWithInsuranceReference(
  PayrollInsuranceBasisRpc rpc, Map<String, dynamic> scope,
) async {
  final raw = await rpc('read_worker_payroll_tax_conditions', scope);
  bool matches(dynamic result) => result is Map &&
      result['company_id'] == scope['p_company_id'] &&
      result['worker_id'] == scope['p_worker_id'];
  if (!matches(raw)) throw const FormatException('本人・会社の計算条件が一致しません');
  final source = payrollBirthSource(raw as Map);
  if (raw['insurance_basis_reference_contract_version'] != 1) return raw;
  final full = await rpc('read_worker_payroll_tax_conditions_with_insurance_reference', scope);
  if (!matches(full) || full is! Map || full['insurance_basis_reference_contract_version'] != 1) {
    throw const FormatException('保存済みの対象期間・平均月収を確認できません');
  }
  final fullSource = payrollBirthSource(full);
  if (full.containsKey('birth_source') && fullSource != source) {
    throw const FormatException('誕生日の参照元が一致しません');
  }
  return source != null ? {...full, 'birth_source': source} : full;
}

/// Uses the authenticated bounded reader; no service credential or direct table read.
class PayrollInsuranceIncomeHistoryRepository {
  const PayrollInsuranceIncomeHistoryRepository(this.rpc);
  final PayrollInsuranceBasisRpc rpc;

  Future<PayrollInsuranceIncomeHistory> read({required String companyId,
    required String workerId, required String from, required String to}) async {
    final months = payrollReferenceMonths(from, to);
    final raw = await rpc('read_worker_payroll_insurance_income_history', {
      'p_company_id': companyId, 'p_worker_id': workerId,
      'p_from': from, 'p_to': to,
    });
    if (raw is! Map || raw['contract_version'] != 1 ||
        raw['company_id'] != companyId || raw['worker_id'] != workerId ||
        raw['from'] != from || raw['to'] != to || raw['items'] is! List ||
        raw['history_fingerprint'] is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(raw['history_fingerprint'] as String)) {
      throw const FormatException('本人・会社・対象期間の実績を確認できません');
    }
    final rows = <PayrollInsuranceIncomeMonth>[];
    final seen = <String>{};
    for (final item in raw['items'] as List) {
      if (item is! Map || item['statement_id'] is! String ||
          (item['statement_id'] as String).isEmpty || item['month'] is! String ||
          !months.contains(item['month']) || !seen.add(item['month'] as String) ||
          item['gross_pay'] is! int || (item['gross_pay'] as int) < 0 ||
          (item['gross_pay'] as int) > 2147483647 || item['finalized'] is! bool ||
          item['revision'] is! int || (item['revision'] as int) < 1 ||
          (item['payment_date'] != null && item['payment_date'] is! String)) {
        throw const FormatException('実績の月・支給総額・確定状態を確認できません');
      }
      rows.add(PayrollInsuranceIncomeMonth(statementId: item['statement_id'] as String,
        month: item['month'] as String, grossPay: item['gross_pay'] as int,
        finalized: item['finalized'] as bool, revision: item['revision'] as int,
        paymentDate: item['payment_date'] as String?));
    }
    rows.sort((a, b) => a.month.compareTo(b.month));
    return PayrollInsuranceIncomeHistory(from: from, to: to, items: List.unmodifiable(rows),
      fingerprint: raw['history_fingerprint'] as String);
  }
}
