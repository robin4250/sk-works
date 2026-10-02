String domesticPhoneDisplay(String? value) {
  var text = value?.trim() ?? '';
  if (text.isEmpty) return '';

  if (text.startsWith('+81')) {
    text = text.substring(3).trimLeft();
    while (text.startsWith('-') || text.startsWith(' ')) {
      text = text.substring(1);
    }
    return '0$text';
  }

  final compact = text.replaceAll(RegExp(r'\s+'), '');
  if (compact.startsWith('81') && compact.length >= 11) {
    return '0${compact.substring(2)}';
  }
  return text;
}
