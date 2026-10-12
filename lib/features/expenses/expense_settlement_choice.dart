enum ExpenseSettlementMethod { cash, payroll }

class ExpenseSettlementChoice {
  ExpenseSettlementChoice(this.method, DateTime month)
    : month = DateTime.utc(month.year, month.month) {
    if (month.day != 1 || month.year < 1900 || month.year > 9999) {
      throw ArgumentError('精算対象月を確認してください。');
    }
  }
  /// Application month is the civil month in Japan, never the expense date.
  static DateTime applicationMonth(DateTime submittedAt) {
    final japan = submittedAt.toUtc().add(const Duration(hours: 9));
    return DateTime.utc(japan.year, japan.month);
  }

  final ExpenseSettlementMethod method;
  final DateTime month;
  String get monthKey => '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}-01';
  String get label => method == ExpenseSettlementMethod.cash ? '現金精算' : '給料精算';
  factory ExpenseSettlementChoice.decode(Object? method, Object? month) {
    if (method is! String || month is! String || !RegExp(r'^\d{4}-\d{2}-01$').hasMatch(month)) {
      throw StateError('精算方法・対象月を確認できません。');
    }
    final result = ExpenseSettlementChoice(ExpenseSettlementMethod.values.byName(method), DateTime.parse(month));
    if (result.monthKey != month) throw StateError('精算対象月を確認できません。');
    return result;
  }
  bool sameAs(ExpenseSettlementChoice other) => method == other.method && month == other.month;
}
