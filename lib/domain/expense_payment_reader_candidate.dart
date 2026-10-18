import 'expense_cost_direction_v2_candidate.dart';
import 'expense_cost_snapshot.dart';

/// Independent non-expense calculation evidence, not derived by reversing a
/// saved v1 gross. A future backend adapter must bind it to the same revision.
class ExpensePaymentBasisCandidate {
  const ExpensePaymentBasisCandidate({
    required this.context,
    required this.grossBeforeExpenseYen,
    required this.otherDeductionsYen,
  });
  final ExpenseCostContext context;
  final int grossBeforeExpenseYen, otherDeductionsYen;
}

/// Read-only payment consumer boundary, currently disconnected from production.
class ExpensePaymentReadCandidate {
  ExpensePaymentReadCandidate._({
    required this.grossYen,
    required this.deductionsYen,
    required this.netYen,
    required this.legacyCost,
    required this.directionalCost,
  });
  final int grossYen, deductionsYen, netYen;
  final ExpenseCostSnapshot? legacyCost;
  final ExpenseCostDirectionV2Candidate? directionalCost;
  bool get usesV2 => directionalCost != null;
  int get expenseLineDeltaYen =>
      directionalCost?.signedDeltaYen ?? legacyCost!.amountYen;

  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static const _max = 9007199254740991;
  static bool _nonnegative(Object? value) =>
      value is int && value >= 0 && value <= _max;
  static bool _signed(Object? value) =>
      value is int && value >= -_max && value <= _max;
  static bool _sameContext(ExpenseCostContext a, ExpenseCostContext b) =>
      a.kind == b.kind &&
      a.companyId == b.companyId &&
      a.documentId == b.documentId &&
      a.subjectId == b.subjectId &&
      a.month == b.month &&
      a.documentRevision == b.documentRevision;
  static bool _validPeriod(String start, String end, String month) {
    final pattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    final first = DateTime.tryParse(start), last = DateTime.tryParse(end);
    return pattern.hasMatch(start) &&
        pattern.hasMatch(end) &&
        first != null &&
        last != null &&
        start ==
            '${first.year.toString().padLeft(4, '0')}-${first.month.toString().padLeft(2, '0')}-${first.day.toString().padLeft(2, '0')}' &&
        end ==
            '${last.year.toString().padLeft(4, '0')}-${last.month.toString().padLeft(2, '0')}-${last.day.toString().padLeft(2, '0')}' &&
        start.startsWith('$month-') &&
        end.startsWith('$month-') &&
        !last.isBefore(first);
  }

  /// New nested snapshot key is a candidate boundary, not a deployed schema.
  /// Legacy snapshots remain additive; no v1 values are converted into v2.
  factory ExpensePaymentReadCandidate.read({
    required Map<String, dynamic> row,
    required ExpenseCostContext expected,
    required String expectedPeriodStart,
    required String expectedPeriodEnd,
    required Iterable<Map<String, dynamic>> legacyDetails,
    bool v2ContractVerified = false,
    ExpensePaymentBasisCandidate? v2Basis,
    Object? v2ScopedDetails,
  }) {
    if (expected.kind != ExpenseCostDocumentKind.paymentCertificate ||
        ![
          expected.companyId,
          expected.documentId,
          expected.subjectId,
        ].every(_uuid.hasMatch) ||
        expected.documentRevision < 1 ||
        expected.month.startsWith('0000-') ||
        row['company_id'] != expected.companyId ||
        row['id'] != expected.documentId ||
        row['partner_company_id'] != expected.subjectId ||
        row['period_start'] != expectedPeriodStart ||
        row['period_end'] != expectedPeriodEnd ||
        !_validPeriod(expectedPeriodStart, expectedPeriodEnd, expected.month) ||
        row['revision'] is! int ||
        row['revision'] != expected.documentRevision ||
        !_nonnegative(row['gross_amount']) ||
        !_nonnegative(row['deductions']) ||
        !_signed(row['net_amount']) ||
        row['snapshot'] is! Map) {
      throw StateError('支払証明書の固定対象・保存金額を確認できません。');
    }
    final snapshot = Map<String, dynamic>.from(row['snapshot'] as Map);
    final gross = row['gross_amount'] as int,
        deductions = row['deductions'] as int,
        net = row['net_amount'] as int;
    final hasV2 = snapshot.containsKey('expense_cost_direction_v2');
    if (!hasV2) {
      if (v2Basis != null || v2ScopedDetails != null) {
        throw StateError('旧帳票を新方向へ読み替えることはできません。');
      }
      final legacy = ExpenseCostSnapshot.parse(snapshot);
      legacy.verifyDetails(legacyDetails);
      return ExpensePaymentReadCandidate._(
        grossYen: gross,
        deductionsYen: deductions,
        netYen: net,
        legacyCost: legacy,
        directionalCost: null,
      );
    }
    if (!v2ContractVerified ||
        v2Basis == null ||
        !_sameContext(expected, v2Basis.context) ||
        snapshot.keys.any((key) => key.startsWith('expense_extra_'))) {
      throw StateError('方向付き支払の接続条件を確認できません。');
    }
    final cost = ExpenseCostDirectionV2Candidate.parse(
      snapshot['expense_cost_direction_v2'],
      expected: expected,
    );
    cost.verifyDetails(v2ScopedDetails);
    cost.verifyPaymentTotals(
      baseGrossYen: v2Basis.grossBeforeExpenseYen,
      otherDeductionsYen: v2Basis.otherDeductionsYen,
      savedGrossYen: gross,
      savedDeductionsYen: deductions,
      savedNetYen: net,
    );
    return ExpensePaymentReadCandidate._(
      grossYen: gross,
      deductionsYen: deductions,
      netYen: net,
      legacyCost: null,
      directionalCost: cost,
    );
  }
}
