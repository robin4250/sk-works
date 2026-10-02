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
}
