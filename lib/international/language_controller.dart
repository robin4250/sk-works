import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/supabase_backend.dart';
import 'core/language_pack.dart';
import 'language_pack_registry.dart';

class SkoLanguageController {
  SkoLanguageController._();

  static const _prefKey = 'sko_language_code';

  static final ValueNotifier<LanguagePack> pack =
      ValueNotifier<LanguagePack>(LanguagePackRegistry.resolve('ja'));

  static bool _hasLocalPreference = false;

  static String get languageCode => pack.value.languageCode;
  static bool get isEnglish => languageCode == 'en';

  static String tr(String source) => pack.value.translate(source);

  static Future<void> loadLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_prefKey);
    _hasLocalPreference = code != null && code.trim().isNotEmpty;
    pack.value = LanguagePackRegistry.resolve(code);
  }

  static Future<void> syncFromCloud() async {
    if (_hasLocalPreference || !SupabaseBackend.isInitialized) return;
    final user = SupabaseBackend.client.auth.currentUser;
    if (user == null) return;

    final memberships = await SupabaseBackend.client
        .from('company_members')
        .select('company_id')
        .eq('user_id', user.id)
        .limit(1);
    if (memberships.isEmpty) return;

    final companyId = memberships.first['company_id']?.toString();
    if (companyId == null || companyId.isEmpty) return;

    final rows = await SupabaseBackend.client
        .from('company_language_preferences')
        .select('language')
        .eq('company_id', companyId)
        .limit(1);
    if (rows.isEmpty) return;

    final code = rows.first['language']?.toString();
    await _apply(code);
  }

  static Future<void> setLanguage(
    String code, {
    bool saveCloud = true,
  }) async {
    final resolved = LanguagePackRegistry.resolve(code);
    await _apply(resolved.languageCode);

    if (!saveCloud || !SupabaseBackend.isInitialized) return;
    final user = SupabaseBackend.client.auth.currentUser;
    if (user == null) return;

    final memberships = await SupabaseBackend.client
        .from('company_members')
        .select('company_id, role')
        .eq('user_id', user.id)
        .limit(1);
    if (memberships.isEmpty) return;

    final row = memberships.first;
    final role = row['role']?.toString() ?? 'viewer';
    if (role != 'owner' && role != 'admin') return;

    final companyId = row['company_id']?.toString();
    if (companyId == null || companyId.isEmpty) return;

    await SupabaseBackend.client.from('company_language_preferences').upsert({
      'company_id': companyId,
      'language': resolved.languageCode,
    });
  }

  static Future<void> _apply(String? code) async {
    final resolved = LanguagePackRegistry.resolve(code);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, resolved.languageCode);
    _hasLocalPreference = true;
    if (pack.value.languageCode != resolved.languageCode) {
      pack.value = resolved;
    }
  }
}
