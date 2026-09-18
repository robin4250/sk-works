import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import 'product_modules.dart';

class CompanyModuleSettingsRepository {
  CompanyModuleSettingsRepository._(this._client);

  final SupabaseClient _client;

  static CompanyModuleSettingsRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return CompanyModuleSettingsRepository._(client);
  }

  Future<({String companyId, String role})> _membership() async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('SKOへのログインが必要です。');

    final rows = await _client
        .from('company_members')
        .select('company_id, role')
        .eq('user_id', user.id)
        .limit(1);
    if (rows.isEmpty) throw StateError('会社情報が見つかりません。');

    return (
      companyId: rows.first['company_id'] as String,
      role: rows.first['role']?.toString() ?? 'viewer',
    );
  }

  Future<Map<String, bool>> loadOptionalModuleStates() async {
    final membership = await _membership();
    final rows = await _client
        .from('company_module_settings')
        .select('module_key, is_enabled')
        .eq('company_id', membership.companyId);

    final states = <String, bool>{
      for (final module in ProductModules.optional) module.key: true,
    };

    for (final row in List<Map<String, dynamic>>.from(rows)) {
      final key = row['module_key']?.toString();
      if (key != null && states.containsKey(key)) {
        states[key] = row['is_enabled'] == true;
      }
    }
    return states;
  }

  Future<bool> canManage() async {
    final membership = await _membership();
    return membership.role == 'owner' || membership.role == 'admin';
  }

  Future<void> setEnabled(String moduleKey, bool enabled) async {
    if (!ProductModules.optional.any((module) => module.key == moduleKey)) {
      throw ArgumentError.value(moduleKey, 'moduleKey', 'Unknown optional module');
    }

    final membership = await _membership();
    if (membership.role != 'owner' && membership.role != 'admin') {
      throw StateError('モジュール設定はオーナーまたは管理者のみ変更できます。');
    }
    final user = _client.auth.currentUser!;

    await _client.from('company_module_settings').upsert({
      'company_id': membership.companyId,
      'module_key': moduleKey,
      'is_enabled': enabled,
      'updated_by': user.id,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}
