class LineReferenceMatch {
  const LineReferenceMatch({
    required this.input,
    required this.normalizedInput,
    required this.matchedValue,
    required this.isAmbiguous,
  });

  final String input;
  final String normalizedInput;
  final String? matchedValue;
  final bool isAmbiguous;

  bool get isMatched => matchedValue != null && !isAmbiguous;
}

class LineAttendanceReferenceMatcher {
  const LineAttendanceReferenceMatcher();

  LineReferenceMatch match({
    required String input,
    required Iterable<String> candidates,
  }) {
    final normalizedInput = _normalize(input);
    if (normalizedInput.isEmpty) {
      return LineReferenceMatch(
        input: input,
        normalizedInput: normalizedInput,
        matchedValue: null,
        isAmbiguous: false,
      );
    }

    final matches = candidates
        .where((value) => _normalize(value) == normalizedInput)
        .toList(growable: false);

    if (matches.length == 1) {
      return LineReferenceMatch(
        input: input,
        normalizedInput: normalizedInput,
        matchedValue: matches.single,
        isAmbiguous: false,
      );
    }

    return LineReferenceMatch(
      input: input,
      normalizedInput: normalizedInput,
      matchedValue: null,
      isAmbiguous: matches.length > 1,
    );
  }

  String _normalize(String value) {
    return value
        .trim()
        .replaceAll(RegExp(r'[\s　]+'), '')
        .replaceAll('（', '(')
        .replaceAll('）', ')')
        .toLowerCase();
  }
}
