/// Explicit original expenses already included in a saved document total.
/// Legacy detail-only documents do not authorize a monetary addition.
class ExpenseCostSnapshot {
  const ExpenseCostSnapshot.none()
    : isCurrent = false, amountYen = 0, claims = const [];
  ExpenseCostSnapshot._(this.amountYen, List<Map<String, dynamic>> values)
    : isCurrent = true,
      claims = List.unmodifiable(values.map(Map<String, dynamic>.unmodifiable));

  final bool isCurrent;
  final int amountYen;
  final List<Map<String, dynamic>> claims;

  factory ExpenseCostSnapshot.parse(Map<String, dynamic> snapshot) {
    if (!snapshot.containsKey('expense_extra_source_version')) {
      return const ExpenseCostSnapshot.none();
    }
    final amount = snapshot['expense_extra_amount_yen'];
    final raw = snapshot['expense_extra_claims'];
    if (snapshot['expense_extra_source_version'] != 1 || amount is! int ||
        amount < 0 || raw is! List) {
      throw StateError('別途経費の保存内容を確認できません。');
    }
    final entries = <Map<String, dynamic>>[];
    final ids = <String>{};
    var total = 0;
    for (final value in raw) {
      if (value is! Map) throw StateError('別途経費の内訳を確認できません。');
      final row = Map<String, dynamic>.from(value);
      final id = row['id'], revision = row['revision'], yen = row['amount_yen'];
      if (id is! String || id.isEmpty || !ids.add(id) ||
          revision is! int || revision < 1 || yen is! int || yen <= 0) {
        throw StateError('別途経費の内訳を確認できません。');
      }
      total += yen;
      entries.add(row);
    }
    if (total != amount) throw StateError('別途経費の内訳と合計が一致しません。');
    return ExpenseCostSnapshot._(amount, entries);
  }

  Map<String, dynamic> get fields => isCurrent ? {
    'expense_extra_source_version': 1,
    'expense_extra_amount_yen': amountYen,
    'expense_extra_claims': claims,
  } : const {};

  void verifyDetails(Iterable<Map<String, dynamic>> values) {
    if (!isCurrent) return;
    final actual = values.toList();
    final expected = {for (final row in claims) row['id']: row};
    final seen = <String>{};
    if (actual.length != claims.length || actual.any((row) {
      final id = row['id'];
      final saved = expected[id];
      return id is! String || !seen.add(id) || saved == null ||
          row['revision'] != saved['revision'] ||
          row['amount_yen'] != saved['amount_yen'];
    })) {
      throw StateError('別途経費の内訳と保存済みの版が一致しません。');
    }
  }
}
