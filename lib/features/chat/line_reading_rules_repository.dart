import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import 'line_reading_rules.dart';

class LineReadingRulesRepository {
  LineReadingRulesRepository(this.client) : owner = client.auth.currentUser?.id;
  final SupabaseClient client;
  final String? owner;
  static LineReadingRulesRepository? maybeCreate() =>
      SupabaseBackend.isInitialized &&
          SupabaseBackend.client.auth.currentUser != null
      ? LineReadingRulesRepository(SupabaseBackend.client)
      : null;
  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> params,
  ) async {
    if (owner == null || client.auth.currentUser?.id != owner) {
      throw StateError('ログインが変わりました。');
    }
    final result = await client.rpc(name, params: params);
    if (client.auth.currentUser?.id != owner || result is! Map) {
      throw StateError('読み取り設定を確認できません。');
    }
    return Map<String, dynamic>.from(result);
  }

  Future<Map<String, dynamic>> load(String groupId) =>
      _call('line_reading_rules_workspace', {'p_group_id': groupId});
  Future<Map<String, dynamic>> save(
    String groupId,
    int revision,
    List<LineReadingRule> rules,
  ) => _call('save_line_reading_rules', {
    'p_group_id': groupId,
    'p_expected_revision': revision,
    'p_rules': [for (final r in rules) r.toJson()],
  });
}
