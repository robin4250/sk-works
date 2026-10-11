import '../people/phone_display.dart';

String _asciiPhone(String value) => value.split('').map((c) {
  final code = c.codeUnitAt(0);
  if (c == '＋') return '+';
  return code >= 0xff10 && code <= 0xff19
      ? String.fromCharCode(code - 0xfee0)
      : c;
}).join();

Uri? companyPhoneUri(String text) {
  if (!RegExp(r'^[+0-9()（）－ー \t-]+$').hasMatch(_asciiPhone(text))) return null;
  final value = domesticPhoneDisplay(
    _asciiPhone(text),
  ).replaceAll(RegExp(r'[^0-9+]'), '');
  if (!RegExp(r'^0[0-9]{9,10}$').hasMatch(value)) return null;
  return Uri(scheme: 'tel', path: value);
}

Uri companyAddressUri(String address) => Uri.https(
  'www.google.com',
  '/maps/search/',
  {'api': '1', 'query': address.trim()},
);

List<({String text, Uri? uri})> companyNoteParts(String text) {
  final normalized = _asciiPhone(text);
  final matches = RegExp(
    r'(?<![0-9+])(?:0[0-9]{1,4}[-－ー()（） \t]*[0-9]{1,4}[-－ー()（） \t]*[0-9]{3,4}|\+81[-－ー()（） \t]*[0-9]{1,4}[-－ー()（） \t]*[0-9]{1,4}[-－ー()（） \t]*[0-9]{3,4})(?![0-9])',
  ).allMatches(normalized);
  final result = <({String text, Uri? uri})>[];
  var start = 0;
  for (final match in matches) {
    final uri = companyPhoneUri(match.group(0)!);
    if (uri == null) continue;
    if (match.start > start)
      result.add((text: text.substring(start, match.start), uri: null));
    result.add((text: text.substring(match.start, match.end), uri: uri));
    start = match.end;
  }
  if (start < text.length) result.add((text: text.substring(start), uri: null));
  return result;
}
