String japaneseDomesticPhone(Object? value) {
  var text = value?.toString().trim() ?? '';
  if (text.isEmpty) return '';
  text = text.replaceAll(RegExp(r'\s+'), '');
  if (text.startsWith('+81')) {
    text = '0' + text.substring(3);
  } else if (text.startsWith('0081')) {
    text = '0' + text.substring(4);
  } else if (text.startsWith('81') && !text.startsWith('810')) {
    text = '0' + text.substring(2);
  }
  return text;
}
