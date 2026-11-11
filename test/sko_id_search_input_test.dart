import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/chat/sko_id_search_input.dart';

void main() {
  test('suffix and pasted full ID use the same existing search identifier', () {
    expect(skoIdSearchValue('ABC123'), 'SKO-ABC123');
    expect(skoIdSearchValue(' SKO-ABC123 '), 'SKO-ABC123');
    expect(skoIdSearchValue('sko-ABC123'), 'SKO-ABC123');
    expect(skoIdSearchValue(''), '');
    expect(skoIdSearchValue('SKO-'), '');
    expect(skoIdSearchValue('ABC-SKO-123'), 'SKO-ABC-SKO-123');
  });

  test('pasting full ID leaves only editable suffix and a valid cursor', () {
    const formatter = SkoIdSuffixInputFormatter();
    final result = formatter.formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(text: 'SKO-ABC123', selection: TextSelection.collapsed(offset: 10)),
    );
    expect(result.text, 'ABC123');
    expect(result.selection.baseOffset, 6);
    final cleared = formatter.formatEditUpdate(result, TextEditingValue.empty);
    expect(cleared.text, '');
  });

  test('input composition is preserved until committed', () {
    const composing = TextEditingValue(
      text: 'SKO-ABC', selection: TextSelection.collapsed(offset: 7),
      composing: TextRange(start: 4, end: 7),
    );
    expect(const SkoIdSuffixInputFormatter().formatEditUpdate(TextEditingValue.empty, composing), composing);
  });
}
