/// Empty percentages stay unavailable. A typed zero is an explicit condition.
int? historicalPercentBps(String input) {
  final value = input.trim();
  if (!RegExp(r'^\d{1,3}(\.\d{1,2})?$').hasMatch(value)) return null;
  final parts = value.split('.');
  final whole = int.parse(parts.first);
  final fraction = parts.length == 2 ? int.parse(parts.last.padRight(2, '0')) : 0;
  final bps = whole * 100 + fraction;
  return bps <= 10000 ? bps : null;
}
