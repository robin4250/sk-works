import 'package:flutter/services.dart';

/// Keeps the issued ID unchanged; only removes its display prefix from input.
String skoIdSearchSuffix(String input) =>
    input.trim().replaceFirst(RegExp(r'^SKO-', caseSensitive: false), '');

String skoIdSearchValue(String input) {
  final suffix = skoIdSearchSuffix(input);
  return suffix.isEmpty ? '' : 'SKO-$suffix';
}

class SkoIdSuffixInputFormatter extends TextInputFormatter {
  const SkoIdSuffixInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.composing.isCollapsed) return newValue;
    final text = skoIdSearchSuffix(newValue.text);
    if (text == newValue.text) return newValue;
    final removed = newValue.text.length - text.length;
    int offset(int value) => (value - removed).clamp(0, text.length).toInt();
    return TextEditingValue(
      text: text,
      selection: TextSelection(
        baseOffset: offset(newValue.selection.baseOffset),
        extentOffset: offset(newValue.selection.extentOffset),
      ),
    );
  }
}
