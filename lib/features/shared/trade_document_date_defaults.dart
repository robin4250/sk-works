/// Initial values only. Never rewrite a saved monthly appendix.
Map<String, String> tradeDocumentDateDefaults(String month) {
  final match = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(month);
  if (match == null) throw FormatException('対象月を確認してください。');
  final year = int.parse(match.group(1)!);
  final number = int.parse(match.group(2)!);
  if (year < 1 || number < 1 || number > 12) {
    throw FormatException('対象月を確認してください。');
  }
  String date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
  final contract = date(DateTime(year, number - 1, 15));
  return {
    'issue_date': contract,
    'order_date': contract,
    'period_start': date(DateTime(year, number, 1)),
    'period_end': date(DateTime(year, number + 1, 0)),
  };
}
