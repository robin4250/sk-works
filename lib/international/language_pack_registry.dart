import 'core/language_pack.dart';
import 'languages/ja/japanese_language_pack.dart';

class LanguagePackRegistry {
  const LanguagePackRegistry._();

  static const Map<String, LanguagePack> supported = <String, LanguagePack>{
    'ja': japaneseLanguagePack,
  };

  static LanguagePack resolve(String? languageCode) {
    final normalized = languageCode?.trim().toLowerCase().split(RegExp('[-_]')).first;
    if (normalized == null || normalized.isEmpty) return japaneseLanguagePack;
    return supported[normalized] ?? japaneseLanguagePack;
  }
}
