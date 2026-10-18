import 'expense_cost_snapshot.dart';

/// Review-only contract. No production reader, generator or renderer uses it.
enum ExpenseCostDocumentKind { invoice, paymentCertificate }

enum ExpenseCostDirection { addition, deduction }

class ExpenseCostContext {
  const ExpenseCostContext({
    required this.kind,
    required this.companyId,
    required this.documentId,
    required this.subjectId,
    required this.month,
    required this.documentRevision,
  });
  final ExpenseCostDocumentKind kind;
  final String companyId, documentId, subjectId, month;
  final int documentRevision;
}

class ExpenseCostDirectionV2Candidate {
  ExpenseCostDirectionV2Candidate._(this.context, this.direction, this._cost);

  static const _keys = {
    'version',
    'contract',
    'document_kind',
    'direction',
    'company_id',
    'document_id',
    'subject_id',
    'month',
    'document_revision',
    'amount_yen',
    'claims',
  };
  static const _claimKeys = {'id', 'revision', 'amount_yen'};
  static const _maxExactInteger = 9007199254740991;
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static final _month = RegExp(r'^[0-9]{4}-(0[1-9]|1[0-2])$');

  final ExpenseCostContext context;
  final ExpenseCostDirection direction;
  final ExpenseCostSnapshot _cost;
  int get amountYen => _cost.amountYen;
  int get signedDeltaYen =>
      direction == ExpenseCostDirection.deduction ? -amountYen : amountYen;
  List<Map<String, dynamic>> get claims => _cost.claims;

  static bool _exactKeys(Map value, Set<String> keys) =>
      value.length == keys.length && value.keys.every(keys.contains);
  static bool _money(Object? value) =>
      value is int && value >= 0 && value <= _maxExactInteger;
  static void _checkContext(ExpenseCostContext context) {
    if (![
          context.companyId,
          context.documentId,
          context.subjectId,
        ].every(_uuid.hasMatch) ||
        !_month.hasMatch(context.month) ||
        context.month.startsWith('0000-') ||
        context.documentRevision < 1 ||
        context.documentRevision > _maxExactInteger) {
      throw StateError('帳票の固定対象を確認できません。');
    }
  }

  factory ExpenseCostDirectionV2Candidate.parse(
    Object? raw, {
    required ExpenseCostContext expected,
  }) {
    _checkContext(expected);
    final direction = expected.kind == ExpenseCostDocumentKind.invoice
        ? ExpenseCostDirection.addition
        : ExpenseCostDirection.deduction;
    if (raw is! Map ||
        !_exactKeys(raw, _keys) ||
        raw['version'] is! int ||
        raw['version'] != 2 ||
        raw['contract'] != 'expense_cost_direction' ||
        raw['document_kind'] != expected.kind.name ||
        raw['direction'] != direction.name ||
        raw['company_id'] != expected.companyId ||
        raw['document_id'] != expected.documentId ||
        raw['subject_id'] != expected.subjectId ||
        raw['month'] != expected.month ||
        raw['document_revision'] is! int ||
        raw['document_revision'] != expected.documentRevision ||
        !_money(raw['amount_yen']) ||
        raw['claims'] is! List) {
      throw StateError('方向付き経費の保存契約と帳票対象が一致しません。');
    }
    var sum = 0;
    final ids = <String>{};
    for (final claim in raw['claims'] as List) {
      if (claim is! Map ||
          !_exactKeys(claim, _claimKeys) ||
          claim['id'] is! String ||
          !_uuid.hasMatch(claim['id'] as String) ||
          !ids.add((claim['id'] as String).toLowerCase()) ||
          claim['revision'] is! int ||
          (claim['revision'] as int) < 1 ||
          (claim['revision'] as int) > _maxExactInteger ||
          !_money(claim['amount_yen']) ||
          claim['amount_yen'] == 0) {
        throw StateError('方向付き経費の原額内訳を確認できません。');
      }
      final amount = claim['amount_yen'] as int;
      if (sum > _maxExactInteger - amount) {
        throw StateError('経費の合計を正確に確認できません。');
      }
      sum += amount;
    }
    // Reuse v1's ID/revision/original-amount and immutable detail validation.
    // This is an internal validation projection of an explicit v2 envelope,
    // never an upgrade or reinterpretation of any saved v1 snapshot.
    final validated = ExpenseCostSnapshot.parse({
      'expense_extra_source_version': 1,
      'expense_extra_amount_yen': raw['amount_yen'],
      'expense_extra_claims': raw['claims'],
    });
    return ExpenseCostDirectionV2Candidate._(expected, direction, validated);
  }

  Map<String, dynamic> get fields => Map.unmodifiable({
    'version': 2,
    'contract': 'expense_cost_direction',
    'document_kind': context.kind.name,
    'direction': direction.name,
    'company_id': context.companyId,
    'document_id': context.documentId,
    'subject_id': context.subjectId,
    'month': context.month,
    'document_revision': context.documentRevision,
    'amount_yen': amountYen,
    'claims': claims,
  });

  void verifyDetails(Object? scopedDetails) {
    final details = ExpenseCostDirectionV2Candidate.parse(
      scopedDetails,
      expected: context,
    );
    _cost.verifyDetails(details.claims);
    if (details.amountYen != amountYen) throw StateError('経費原額が一致しません。');
  }

  /// Candidate invariant only. Base total already includes its existing tax and
  /// welfare; the original expense is added once without changing either.
  void verifyInvoiceTotal({
    required int baseTotalYen,
    required int savedTotalYen,
  }) {
    if (context.kind != ExpenseCostDocumentKind.invoice ||
        !_money(baseTotalYen) ||
        !_money(savedTotalYen) ||
        baseTotalYen > _maxExactInteger - amountYen ||
        savedTotalYen != baseTotalYen + signedDeltaYen) {
      throw StateError('請求加算と保存合計が一致しません。');
    }
  }

  /// Candidate invariant only; does not recalculate any saved document.
  void verifyPaymentTotals({
    required int baseGrossYen,
    required int otherDeductionsYen,
    required int savedGrossYen,
    required int savedDeductionsYen,
    required int savedNetYen,
  }) {
    if (context.kind != ExpenseCostDocumentKind.paymentCertificate ||
        ![
          baseGrossYen,
          otherDeductionsYen,
          savedGrossYen,
          savedDeductionsYen,
        ].every(_money) ||
        otherDeductionsYen > _maxExactInteger - amountYen) {
      throw StateError('支払差引の基礎金額を確認できません。');
    }
    // A deduction-only statement may have a negative net (for example -1000).
    // This validates the signed saved amount, not a transfer or carry policy.
    if (savedNetYen < -_maxExactInteger ||
        savedNetYen > _maxExactInteger ||
        savedGrossYen != baseGrossYen ||
        savedDeductionsYen != otherDeductionsYen + amountYen ||
        savedNetYen != baseGrossYen - (otherDeductionsYen + amountYen)) {
      throw StateError('経費差引と支払保存額が一致しません。');
    }
  }
}
