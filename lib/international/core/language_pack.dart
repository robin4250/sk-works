class LanguagePack {
  const LanguagePack({
    required this.languageCode,
    required this.fallbackLanguageCode,
    this.strings = const <String, String>{},
  });

  final String languageCode;
  final String fallbackLanguageCode;
  final Map<String, String> strings;

  String translate(String source) => strings[source] ?? source;

  /// Translate a fixed template, then insert values verbatim.
  /// Company names, amounts and server error details are never translated.
  String format(String source, Map<String, Object?> parameters) {
    final template = translate(source);
    return template.replaceAllMapped(RegExp(r'\{([A-Za-z][A-Za-z0-9_]*)\}'),
        (match) {
      final key = match.group(1)!;
      return parameters.containsKey(key)
          ? (parameters[key]?.toString() ?? '')
          : match.group(0)!;
    });
  }
}
